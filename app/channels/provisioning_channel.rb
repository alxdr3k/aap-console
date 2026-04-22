class ProvisioningChannel < ApplicationCable::Channel
  def subscribed
    job = ProvisioningJob.find_by(id: params[:job_id])
    return reject unless job.present?

    return reject unless authorized?(job)

    stream_for job, coder: ActiveSupport::JSON
  end

  def unsubscribed
    stop_all_streams
  end

  private

  def authorized?(job)
    user_sub = connection.current_user_sub
    return false unless user_sub.present?

    project = job.project
    organization = project.organization

    membership = OrgMembership.find_by(organization: organization, user_sub: user_sub)
    return false unless membership.present?

    return true if membership.admin?

    ProjectPermission.exists?(
      org_membership: membership,
      project: project
    )
  end
end
