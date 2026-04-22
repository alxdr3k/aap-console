class AuthConfigsController < ApplicationController
  before_action :set_organization
  before_action :set_project
  before_action -> { authorize_project!(@project) }, only: [:show]
  before_action -> { authorize_project!(@project, minimum_role: :write) }, only: [:update]

  def show
    config = @project.project_auth_config
    if config
      render json: config
    else
      render json: { error: "Not found" }, status: :not_found
    end
  end

  def update
    config = @project.project_auth_config || @project.build_project_auth_config

    if config.update(auth_config_params)
      AuditLog.create!(
        organization: @organization,
        project: @project,
        user_sub: Current.user_sub,
        action: "auth_config.update",
        resource_type: "ProjectAuthConfig",
        resource_id: config.id.to_s,
        details: { auth_type: config.auth_type }
      )
      render json: config
    else
      render json: { errors: config.errors.full_messages }, status: :unprocessable_entity
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

  def auth_config_params
    params.require(:auth_config).permit(:keycloak_client_id, :keycloak_client_uuid)
  end
end
