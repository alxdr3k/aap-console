class ProvisioningJobsController < ApplicationController
  before_action :set_job
  before_action :authorize_job_access!
  before_action :authorize_job_write!, only: [:retry, :secrets]

  def show
    render json: {
      id: @job.id,
      operation: @job.operation,
      status: @job.status,
      started_at: @job.started_at,
      completed_at: @job.completed_at,
      error_message: @job.error_message,
      warnings: @job.warnings,
      steps: @job.provisioning_steps.order(:step_order, :id).map do |step|
        {
          id: step.id,
          name: step.name,
          step_order: step.step_order,
          status: step.status,
          started_at: step.started_at,
          completed_at: step.completed_at,
          error_message: step.error_message,
          retry_count: step.retry_count
        }
      end
    }
  end

  def retry
    if @job.failed? || @job.rollback_failed?
      @job.update!(status: :pending, error_message: nil)
      ProvisioningExecuteJob.perform_later(@job.id, current_user_sub: Current.user_sub)
      render json: { message: "Job re-enqueued", id: @job.id }
    else
      render json: { error: "Job is not in a retryable state" }, status: :unprocessable_entity
    end
  end

  def secrets
    cached = Rails.cache.read("provisioning_job_secrets_#{@job.id}")
    render json: cached || {}
  end

  private

  def set_job
    @job = ProvisioningJob.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Not found" }, status: :not_found
  end

  def authorize_job_access!
    project = @job.project
    organization = project.organization
    return if current_authorization.super_admin?

    membership = current_authorization.org_membership(organization)
    unless membership
      render_forbidden and return
    end

    unless membership.admin?
      role = current_authorization.project_role(project)
      render_forbidden and return unless role
    end
  end

  def authorize_job_write!
    project = @job.project
    return if current_authorization.super_admin?

    role = current_authorization.project_role(project)
    unless role && role_sufficient?(role, :write)
      render_forbidden
    end
  end

  def role_sufficient?(actual_role, required_role)
    hierarchy = { read: 1, write: 2, admin: 3 }
    hierarchy.fetch(actual_role.to_sym, 0) >= hierarchy.fetch(required_role.to_sym, 0)
  end
end
