class OrganizationDestroyFinalizeJob < ApplicationJob
  RETRY_DELAY = 30.seconds
  BLOCKED_RETRY_DELAY = 5.minutes
  FINALIZER_LEASE_DURATION = 10.minutes

  queue_as :default

  class << self
    def enqueue_once(organization, current_user_sub:)
      organization.with_lock do
        unless finalizer_reserved?(organization)
          reserve_finalizer!(organization)
          set(wait: RETRY_DELAY).perform_later(organization.id, current_user_sub: current_user_sub)
        end
      end
    end

    def reschedule!(organization, current_user_sub:, wait: RETRY_DELAY)
      organization.with_lock do
        reserve_finalizer!(organization)
        set(wait: wait).perform_later(organization.id, current_user_sub: current_user_sub)
      end
    end

    private

    def finalizer_reserved?(organization)
      organization.destroy_finalizer_reserved_until.present? &&
        organization.destroy_finalizer_reserved_until.future?
    end

    def reserve_finalizer!(organization)
      organization.update!(destroy_finalizer_reserved_until: FINALIZER_LEASE_DURATION.from_now)
    end
  end

  # Reads org and projects WITHOUT a row lock by design.
  # Duplicate enqueues are prevented by the destroy_finalizer_reserved_until
  # lease taken in enqueue_once / reschedule! (both use with_lock).
  # reschedule! and release_reservation! take row locks because they mutate
  # the lease column; the reads here are intentionally optimistic.
  def perform(organization_id, current_user_sub:)
    organization = Organization.find_by(id: organization_id)
    return unless organization

    remaining_projects = organization.projects.where.not(status: :deleted)

    unless remaining_projects.exists?
      finalize_destroy!(organization, current_user_sub)
      return
    end

    if delete_in_progress?(remaining_projects)
      self.class.reschedule!(organization, current_user_sub: current_user_sub)
      return
    end

    # No active delete job, but the destroy contract is still pending. Enqueue
    # the longer background retry FIRST. Only after the replacement job has
    # been durably persisted by the queue do we release the finalizer
    # reservation. The Rails 8 default `enqueue_after_transaction_commit =
    # :always` makes a transaction-wrapped `perform_later` defer the queue
    # write past commit, so we deliberately stay outside any transaction here
    # and rely on synchronous enqueue ordering: if the enqueue raises, the
    # lease stays held and an existing operator-driven retry path can still
    # fire. The lease release runs only on a successful enqueue.
    Rails.logger.warn(
      "[OrganizationDestroyFinalizeJob] Organization #{organization.id} destroy is blocked; " \
      "remaining projects: #{remaining_projects.map { |project| "#{project.slug}:#{project.status}" }.join(', ')}; " \
      "rescheduling in #{BLOCKED_RETRY_DELAY.inspect} and releasing reservation"
    )
    self.class.set(wait: BLOCKED_RETRY_DELAY).perform_later(organization.id, current_user_sub: current_user_sub)
    organization.with_lock do
      organization.update!(destroy_finalizer_reserved_until: nil)
    end
  end

  private

  def finalize_destroy!(organization, current_user_sub)
    result = Organizations::DestroyService.new(
      organization: organization,
      current_user_sub: current_user_sub
    ).call

    if result.success?
      self.class.reschedule!(organization, current_user_sub: current_user_sub) if result.data.is_a?(Hash) && result.data[:deferred]
      return
    end

    Rails.logger.error(
      "[OrganizationDestroyFinalizeJob] Failed to finalize organization " \
      "#{organization.id} destroy: #{result.error}"
    )
    self.class.reschedule!(organization, current_user_sub: current_user_sub)
  end

  def delete_in_progress?(projects)
    projects.any? do |project|
      project.provisioning_jobs.where(operation: "delete", status: ProvisioningJob::ACTIVE_STATUSES).exists?
    end
  end
end
