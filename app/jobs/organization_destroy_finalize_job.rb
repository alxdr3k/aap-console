class OrganizationDestroyFinalizeJob < ApplicationJob
  RETRY_DELAY = 30.seconds

  queue_as :default

  class << self
    def enqueue_once(organization_id, current_user_sub:)
      return if enqueued_for_organization?(organization_id)

      set(wait: RETRY_DELAY).perform_later(organization_id, current_user_sub: current_user_sub)
    end

    def enqueued_for_organization?(organization_id)
      test_adapter_enqueued_for_organization?(organization_id) ||
        solid_queue_enqueued_for_organization?(organization_id)
    end

    private

    def test_adapter_enqueued_for_organization?(organization_id)
      return false unless queue_adapter.respond_to?(:enqueued_jobs)

      queue_adapter.enqueued_jobs.any? do |job|
        job_class_name(job) == name && organization_arg_matches?(job_args(job).first, organization_id)
      end
    end

    def solid_queue_enqueued_for_organization?(organization_id)
      return false unless defined?(SolidQueue::Job)

      SolidQueue::Job
        .where(class_name: name, finished_at: nil)
        .find_each
        .any? { |job| solid_queue_arguments_match?(job.arguments, organization_id) }
    rescue ActiveRecord::ActiveRecordError
      false
    end

    def solid_queue_arguments_match?(arguments, organization_id)
      payload = arguments.is_a?(String) ? JSON.parse(arguments) : arguments
      organization_arg_matches?(Array(payload["arguments"] || payload[:arguments]).first, organization_id)
    rescue JSON::ParserError, TypeError
      false
    end

    def job_class_name(job)
      job_class = job[:job] || job["job"] || job[:job_class] || job["job_class"]
      job_class.respond_to?(:name) ? job_class.name : job_class.to_s
    end

    def job_args(job)
      Array(job[:args] || job["args"] || job[:arguments] || job["arguments"])
    end

    def organization_arg_matches?(argument, organization_id)
      argument.to_s == organization_id.to_s
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
      self.class.set(wait: RETRY_DELAY).perform_later(organization.id, current_user_sub: current_user_sub)
      return
    end

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
      reschedule_deferred_destroy!(organization.id, current_user_sub) if result.data.is_a?(Hash) && result.data[:deferred]
      return
    end

    Rails.logger.error(
      "[OrganizationDestroyFinalizeJob] Failed to finalize organization " \
      "#{organization.id} destroy: #{result.error}"
    )
    self.class.set(wait: RETRY_DELAY).perform_later(organization.id, current_user_sub: current_user_sub)
  end

  def delete_in_progress?(projects)
    projects.any? do |project|
      project.provisioning_jobs.where(operation: "delete", status: ProvisioningJob::ACTIVE_STATUSES).exists?
    end
  end

  def reschedule_deferred_destroy!(organization_id, current_user_sub)
    self.class.set(wait: RETRY_DELAY).perform_later(organization_id, current_user_sub: current_user_sub)
  end
end
