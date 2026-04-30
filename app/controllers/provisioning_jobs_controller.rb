class ProvisioningJobsController < ApplicationController
  before_action :set_job
  before_action :authorize_job_access!
  before_action :set_step, only: [ :step ]
  before_action :authorize_job_write!, only: [ :retry, :secrets ]

  def show
    @project = @job.project
    @organization = @project.organization
    @steps = @job.provisioning_steps.order(:step_order, :id)

    return render json: provisioning_job_payload if default_json_request?

    respond_to do |format|
      format.html
      format.json { render json: provisioning_job_payload }
    end
  end

  def retry
    return retry_error("Job is not in a retryable state", :unprocessable_entity) unless @job.retryable?
    return retry_error("Another provisioning job is in progress", :conflict) if retry_conflict?

    ActiveRecord::Base.transaction do
      reset_project_for_retry!
      @job.update!(status: :retrying, error_message: nil, completed_at: nil)
    end

    ProvisioningExecuteJob.perform_later(@job.id, current_user_sub: Current.user_sub)
    retry_success
  rescue ActiveRecord::RecordNotUnique
    retry_error("Another provisioning job is in progress", :conflict)
  end

  def secrets
    disable_secret_response_cache!
    return render json: {} unless @job.completed? || @job.completed_with_warnings?

    render json: Provisioning::SecretCache.read(@job)
  end

  def step
    return render json: provisioning_step_payload(@step) if default_json_request?

    respond_to do |format|
      format.html { render partial: "step", locals: { step: @step } }
      format.json { render json: provisioning_step_payload(@step) }
    end
  end

  private

  def provisioning_job_payload
    {
      id: @job.id,
      operation: @job.operation,
      status: @job.status,
      started_at: @job.started_at,
      completed_at: @job.completed_at,
      error_message: @job.error_message,
      warnings: @job.warnings,
      steps: @job.provisioning_steps.order(:step_order, :id).map do |step|
        provisioning_step_payload(step)
      end
    }
  end

  def provisioning_step_payload(step)
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

  def set_job
    @job = ProvisioningJob.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    return render json: { error: "Not found" }, status: :not_found if default_json_request?

    respond_to do |format|
      format.html { render :not_found, status: :not_found }
      format.json { render json: { error: "Not found" }, status: :not_found }
    end
  end

  def set_step
    @step = @job.provisioning_steps.find(params[:step_id])
  rescue ActiveRecord::RecordNotFound
    return render json: { error: "Not found" }, status: :not_found if default_json_request?

    respond_to do |format|
      format.html { render plain: "Not found", status: :not_found }
      format.json { render json: { error: "Not found" }, status: :not_found }
    end
  end

  def disable_secret_response_cache!
    response.headers["Cache-Control"] = "no-store"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"
  end

  def retry_success
    return render json: { message: "Job re-enqueued", id: @job.id, status: @job.status } if default_json_request?

    respond_to do |format|
      format.html do
        flash[:success] = "프로비저닝 재시도를 시작했습니다."
        redirect_to provisioning_job_path(@job), status: :see_other
      end
      format.json { render json: { message: "Job re-enqueued", id: @job.id, status: @job.status } }
    end
  end

  def retry_error(message, status)
    return render json: { error: message }, status: status if default_json_request?

    respond_to do |format|
      format.html do
        flash[:alert] = message
        redirect_to provisioning_job_path(@job), status: :see_other
      end
      format.json { render json: { error: message }, status: status }
    end
  end

  def retry_conflict?
    @job.project.provisioning_jobs
        .where(status: ProvisioningJob::ACTIVE_STATUSES)
        .where.not(id: @job.id)
        .exists?
  end

  def reset_project_for_retry!
    case @job.operation
    when "create"
      @job.project.update!(status: :provisioning)
    when "update"
      @job.project.update!(status: :update_pending)
    when "delete"
      @job.project.update!(status: :deleting)
    end
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
      render_forbidden and return
    end
  end

  def role_sufficient?(actual_role, required_role)
    hierarchy = { read: 1, write: 2, admin: 3 }
    hierarchy.fetch(actual_role.to_sym, 0) >= hierarchy.fetch(required_role.to_sym, 0)
  end
end
