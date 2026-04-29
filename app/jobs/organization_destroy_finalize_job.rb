class OrganizationDestroyFinalizeJob < ApplicationJob
  RETRY_DELAY = 30.seconds
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

    def reschedule!(organization, current_user_sub:)
      organization.with_lock do
        reserve_finalizer!(organization)
        set(wait: RETRY_DELAY).perform_later(organization.id, current_user_sub: current_user_sub)
      end
    end

    def release_reservation!(organization)
      organization.with_lock do
        organization.update!(destroy_finalizer_reserved_until: nil)
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

    self.class.release_reservation!(organization)
    Rails.logger.error(
      "[OrganizationDestroyFinalizeJob] Organization #{organization.id} destroy is blocked; " \
      "remaining projects: #{remaining_projects.map { |project| "#{project.slug}:#{project.status}" }.join(', ')}"
    )
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
