class AuthConfigsController < ApplicationController
  before_action :set_organization
  before_action :set_project
  before_action :set_auth_config
  before_action -> { authorize_project!(@project) }, only: [ :show ]
  before_action -> { authorize_project!(@project, minimum_role: :write) }, only: [ :update, :regenerate_secret ]

  def show
    return render_auth_config_not_found unless @auth_config
    return render json: @auth_config if json_request?

    prepare_show
    disable_secret_response_cache! if @secret_entries.present? || @project_api_key_reveal.present?

    respond_to do |format|
      format.html
      format.json { render json: @auth_config }
    end
  end

  # Auth config mutations go through Projects::UpdateService so that any
  # change which requires Keycloak propagation is enqueued as an update
  # provisioning job. Keycloak identifiers (client_id, client_uuid) are
  # server-owned and must not be writable by clients.
  def update
    return render_auth_config_not_found unless @auth_config

    result = Projects::UpdateService.new(
      project: @project,
      params: permitted_auth_params,
      current_user_sub: Current.user_sub
    ).call

    if result.success?
      provisioning_job = result.data[:provisioning_job]

      if json_request?
        if provisioning_job
          render json: { provisioning_job_id: provisioning_job.id }, status: :accepted
        else
          render json: { message: "Auth config updated" }, status: :ok
        end
      elsif provisioning_job
        flash[:success] = "인증 설정 변경 프로비저닝을 시작했습니다."
        redirect_to provisioning_job_path(provisioning_job), status: :see_other
      else
        flash[:success] = "인증 설정이 저장되었습니다."
        redirect_to organization_project_auth_config_path(@organization.slug, @project.slug), status: :see_other
      end
    else
      return render json: { error: result.error }, status: :unprocessable_entity if json_request?

      @errors = [ result.error ]
      prepare_show(form_values: permitted_auth_params)
      render :show, status: :unprocessable_entity
    end
  end

  def regenerate_secret
    return render_auth_config_not_found unless @auth_config

    result = AuthConfigs::RegenerateClientSecretService.new(
      project: @project,
      current_user_sub: Current.user_sub
    ).call

    if result.success?
      if json_request?
        disable_secret_response_cache!
        render json: AuthConfigs::SecretRevealCache.read(@project), status: :created
      else
        flash[:warning] = "Client Secret이 재발급되었습니다. 기존 Secret은 즉시 무효화됩니다."
        redirect_to organization_project_auth_config_path(@organization.slug, @project.slug), status: :see_other
      end
    else
      return render json: { errors: [ result.error ] }, status: :unprocessable_entity if json_request?

      @errors = [ result.error ]
      prepare_show
      render :show, status: :unprocessable_entity
    end
  end

  private

  def set_organization
    @organization = Organization.find_by!(slug: params[:organization_slug])
  rescue ActiveRecord::RecordNotFound
    return render json: { error: "Not found" }, status: :not_found if json_request?

    respond_to do |format|
      format.html { render "projects/not_found", status: :not_found }
      format.json { render json: { error: "Not found" }, status: :not_found }
    end
  end

  def set_project
    @project = @organization.projects.find_by!(slug: params[:project_slug])
  rescue ActiveRecord::RecordNotFound
    return render json: { error: "Not found" }, status: :not_found if json_request?

    respond_to do |format|
      format.html { render "projects/not_found", status: :not_found }
      format.json { render json: { error: "Not found" }, status: :not_found }
    end
  end

  def set_auth_config
    @auth_config = @project&.project_auth_config
  end

  # Only user-facing auth settings are accepted. Keycloak identifiers
  # (keycloak_client_id, keycloak_client_uuid) are set by the provisioning
  # pipeline and are read-only to the API surface.
  def permitted_auth_params
    permitted = params
      .require(:auth_config)
      .permit(redirect_uris: [], post_logout_redirect_uris: [])

    normalized = {}
    if permitted.key?(:redirect_uris)
      normalized[:redirect_uris] = normalize_uri_values(permitted[:redirect_uris])
    end
    if permitted.key?(:post_logout_redirect_uris)
      normalized[:post_logout_redirect_uris] = normalize_uri_values(permitted[:post_logout_redirect_uris])
    end
    normalized
  end

  def prepare_show(form_values: nil)
    base_values = {
      redirect_uris: @auth_config&.redirect_uris,
      post_logout_redirect_uris: @auth_config&.post_logout_redirect_uris
    }
    values = base_values.merge(form_values || {})

    @errors ||= []
    @can_write_project = current_authorization.can?(:write_project, @project)
    @active_provisioning_job = @project.provisioning_jobs
                                      .where(status: ProvisioningJob::ACTIVE_STATUSES)
                                      .order(created_at: :desc)
                                      .first
    @redirect_uris = form_rows(values[:redirect_uris])
    @post_logout_redirect_uris = form_rows(values[:post_logout_redirect_uris])
    @secret_payload = @can_write_project ? AuthConfigs::SecretRevealCache.read(@project) : {}
    @secret_entries = @secret_payload.fetch("secrets", {})
    @secret_reveal_storage_key = [
      "auth-config-secret",
      @project.id,
      @secret_payload["generated_at"].presence || "current"
    ].join(":")
    @project_api_keys = @project.project_api_keys.order(created_at: :desc)
    @project_api_key_reveal_payload = @can_write_project ? project_api_key_reveal_payload : {}
    @project_api_key_reveal = @project_api_key_reveal_payload.dig("secrets", "project_api_key") || {}
    @project_api_key_reveal_storage_key = [
      "project-api-key",
      @project.id,
      @project_api_key_reveal_payload["generated_at"].presence || "current"
    ].join(":")
    @last_secret_regenerated_at = @project.audit_logs
                                          .where(action: "auth_config.secret_regenerated")
                                          .order(created_at: :desc)
                                          .pick(:created_at)
  end

  def form_rows(values)
    rows = normalize_uri_values(values)
    rows.presence || [ "" ]
  end

  def normalize_uri_values(values)
    Array(values).map(&:to_s).map(&:strip).reject(&:blank?)
  end

  def render_auth_config_not_found
    return render json: { error: "Not found" }, status: :not_found if json_request?

    respond_to do |format|
      format.html { render "projects/not_found", status: :not_found }
      format.json { render json: { error: "Not found" }, status: :not_found }
    end
  end

  def disable_secret_response_cache!
    response.headers["Cache-Control"] = "no-store"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"
  end

  def project_api_key_reveal_payload
    session_payload = session_project_api_key_reveal_payload
    return session_payload if session_payload.present?

    cache_payload = ProjectApiKeys::RevealCache.read(@project)
    return cache_payload if cache_payload.dig("secrets", "project_api_key").present?

    {}
  end

  def session_project_api_key_reveal_payload
    fallbacks = session[:project_api_key_reveal_fallbacks]
    return {} unless fallbacks.is_a?(Hash)

    payload = fallbacks[@project.id.to_s]
    return {} unless payload.is_a?(Hash)
    return clear_session_project_api_key_reveal_payload unless payload["organization_id"] == @project.organization_id
    return clear_session_project_api_key_reveal_payload unless payload["project_id"] == @project.id

    expires_at = Time.zone.iso8601(payload["expires_at"])
    if expires_at.future?
      fallbacks.delete(@project.id.to_s)
      return payload
    end
  rescue ArgumentError
    clear_session_project_api_key_reveal_payload
  else
    clear_session_project_api_key_reveal_payload
  end

  def clear_session_project_api_key_reveal_payload
    fallbacks = session[:project_api_key_reveal_fallbacks]
    return {} unless fallbacks.is_a?(Hash)

    fallbacks.delete(@project.id.to_s)
    {}
  end
end
