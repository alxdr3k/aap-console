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

  # FR-8 ConfigVersion rollback is not yet implemented in the provisioning
  # pipeline — the StepSeeder has no plan for rolling back to a target version
  # and the previous implementation enqueued a stepless update Job that
  # immediately fails. Returning 501 here keeps the route reachable for
  # forward compatibility but signals "do not call yet" instead of silently
  # creating broken jobs. The audit log is still written so we can see who
  # tried and when.
  def rollback
    project = @config_version.project
    organization = project.organization

    AuditLog.create!(
      organization: organization,
      project: project,
      user_sub: Current.user_sub,
      action: "config.rollback.attempted",
      resource_type: "ConfigVersion",
      resource_id: @config_version.id.to_s,
      details: { target_version_id: @config_version.version_id, status: "not_implemented" }
    )

    render json: {
      error: "ConfigVersion rollback is not yet implemented",
      status: "not_implemented"
    }, status: :not_implemented
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
