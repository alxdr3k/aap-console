class ConfigVersionsController < ApplicationController
  before_action :set_config_version, only: [ :show, :rollback ]
  before_action :authorize_config_version_read!, only: [ :show ]
  before_action :authorize_config_version_write!, only: [ :rollback ]

  def index
    @organization = Organization.find_by!(slug: params[:organization_slug])
    @project = @organization.projects.find_by!(slug: params[:project_slug])
    authorize_project!(@project)
    return if performed?
    versions = @project.config_versions.order(created_at: :desc)
    render json: versions
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Not found" }, status: :not_found
  end

  def show
    render json: @config_version
  end

  def rollback
    project = @config_version.project
    organization = project.organization

    ActiveRecord::Base.transaction do
      provisioning_job = project.provisioning_jobs.create!(
        operation: "update",
        status: :pending
      )

      AuditLog.create!(
        organization: organization,
        project: project,
        user_sub: Current.user_sub,
        action: "config.rollback",
        resource_type: "ConfigVersion",
        resource_id: @config_version.id.to_s,
        details: { target_version_id: @config_version.version_id }
      )

      ProvisioningExecuteJob.perform_later(
        provisioning_job.id,
        rollback_to_version_id: @config_version.version_id,
        current_user_sub: Current.user_sub
      )

      redirect_to provisioning_job_path(provisioning_job), status: :see_other
    end
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Not found" }, status: :not_found
  end

  private

  def set_config_version
    @config_version = ConfigVersion.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Not found" }, status: :not_found
  end

  def authorize_config_version_read!
    return if @config_version.nil?
    authorize_project!(@config_version.project)
  end

  def authorize_config_version_write!
    return if @config_version.nil?
    authorize_project!(@config_version.project, minimum_role: :write)
  end
end
