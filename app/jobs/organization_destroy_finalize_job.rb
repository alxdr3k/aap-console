class OrganizationDestroyFinalizeJob < ApplicationJob
  RETRY_DELAY = 30.seconds

  queue_as :default

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

    return if result.success?

    Rails.logger.error(
      "[OrganizationDestroyFinalizeJob] Failed to finalize organization " \
      "#{organization.id} destroy: #{result.error}"
    )
  end

  def delete_in_progress?(projects)
    projects.any? do |project|
      project.provisioning_jobs.where(operation: "delete", status: ProvisioningJob::ACTIVE_STATUSES).exists?
    end
  end
end
