class LitellmConfigsController < ApplicationController
  before_action :set_organization
  before_action :set_project
  before_action -> { authorize_project!(@project) }, only: [ :show ]
  before_action -> { authorize_project!(@project, minimum_role: :write) }, only: [ :update ]

  def show
    latest_version = @project.config_versions.order(created_at: :desc).first
    render json: latest_version&.snapshot || {}
  end

  # LiteLLM config mutations are routed through Projects::UpdateService and
  # propagate via a provisioning job. The response mirrors AuthConfigsController#update:
  # 202 Accepted + provisioning_job_id when a job is enqueued, 200 OK when no
  # external state needs to change. See docs/02_HLD.md §5.6.
  def update
    result = Projects::UpdateService.new(
      project: @project,
      params: litellm_config_params,
      current_user_sub: Current.user_sub
    ).call

    if result.success?
      provisioning_job = result.data[:provisioning_job]
      if provisioning_job
        render json: { provisioning_job_id: provisioning_job.id }, status: :accepted
      else
        render json: { message: "Config updated" }, status: :ok
      end
    else
      render json: { errors: [ result.error ] }, status: :unprocessable_entity
    end
  end

  private

  def set_organization
    @organization = Organization.find_by!(slug: params[:organization_slug])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Not found" }, status: :not_found
  end

  def set_project
    @project = @organization.projects.find_by!(slug: params[:project_slug])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Not found" }, status: :not_found
  end

  def litellm_config_params
    permitted = params.require(:litellm_config).permit(:s3_retention_days, models: [], guardrails: [])
    permitted.to_h.symbolize_keys
  end
end
