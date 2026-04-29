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
    result = ConfigVersions::RollbackService.new(
      config_version: @config_version,
      current_user_sub: Current.user_sub
    ).call

    if result.success?
      render json: rollback_payload(result.data), status: :ok
    else
      render json: rollback_error_payload(result.error), status: result.error.fetch(:status)
    end
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

  def rollback_payload(data)
    {
      status: "completed",
      target_version_id: @config_version.version_id,
      config_version: data.rollback_version,
      diagnostics: data.diagnostics
    }
  end

  def rollback_error_payload(error)
    {
      status: "failed",
      error: error.fetch(:message),
      target_version_id: @config_version.version_id,
      diagnostics: error.fetch(:diagnostics)
    }
  end
end
