class LitellmConfigsController < ApplicationController
  before_action :set_organization
  before_action :set_project
  before_action -> { authorize_project!(@project) }, only: [:show]
  before_action -> { authorize_project!(@project, minimum_role: :write) }, only: [:update]

  def show
    latest_version = @project.config_versions.order(created_at: :desc).first
    config = latest_version&.snapshot&.fetch("litellm_config", {}) || {}
    render json: config
  end

  def update
    result = Projects::UpdateService.new(
      project: @project,
      params: litellm_config_params,
      current_user_sub: Current.user_sub
    ).call

    if result.success?
      project = result.data
      provisioning_job = project.provisioning_jobs.where(operation: "update").last
      if provisioning_job
        redirect_to provisioning_job_path(provisioning_job), status: :see_other
      else
        render json: { message: "Config updated" }
      end
    else
      render json: { errors: [result.error] }, status: :unprocessable_entity
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
