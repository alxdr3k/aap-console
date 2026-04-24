class AuthConfigsController < ApplicationController
  before_action :set_organization
  before_action :set_project
  before_action -> { authorize_project!(@project) }, only: [ :show ]
  before_action -> { authorize_project!(@project, minimum_role: :write) }, only: [ :update ]

  def show
    config = @project.project_auth_config
    if config
      render json: config
    else
      render json: { error: "Not found" }, status: :not_found
    end
  end

  # Auth config mutations go through Projects::UpdateService so that any
  # change which requires Keycloak propagation is enqueued as an update
  # provisioning job. Keycloak identifiers (client_id, client_uuid) are
  # server-owned and must not be writable by clients.
  def update
    config = @project.project_auth_config
    return render json: { error: "Not found" }, status: :not_found unless config

    result = Projects::UpdateService.new(
      project: @project,
      params: permitted_auth_params,
      current_user_sub: Current.user_sub
    ).call

    if result.success?
      project = result.data
      provisioning_job = project.provisioning_jobs.where(operation: "update").last
      if provisioning_job
        render json: { provisioning_job_id: provisioning_job.id }, status: :accepted
      else
        render json: { message: "Auth config updated" }, status: :ok
      end
    else
      render json: { error: result.error }, status: :unprocessable_entity
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

  # Only user-facing auth settings are accepted. Keycloak identifiers
  # (keycloak_client_id, keycloak_client_uuid) are set by the provisioning
  # pipeline and are read-only to the API surface.
  def permitted_auth_params
    permitted = params
      .require(:auth_config)
      .permit(redirect_uris: [], post_logout_redirect_uris: [])
    permitted.to_h.symbolize_keys
  end
end
