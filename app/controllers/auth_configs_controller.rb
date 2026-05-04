class AuthConfigsController < ApplicationController
  include AuthConfigShowState

  before_action :set_organization
  before_action :set_project
  before_action :set_auth_config
  before_action -> { authorize_project!(@project) }, only: [ :show ]
  before_action -> { authorize_project!(@project, minimum_role: :write) }, only: [ :update, :regenerate_secret ]

  def show
    return render_auth_config_not_found unless @auth_config
    return render json: @auth_config if json_request?

    prepare_auth_config_show!
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

    auth_params = permitted_auth_params

    if @auth_config.auth_type == "oauth"
      uri_errors = pkce_redirect_uri_errors(auth_params[:redirect_uris] || [])
      if uri_errors.any?
        return render json: { errors: uri_errors }, status: :unprocessable_entity if json_request?

        @errors = uri_errors
        prepare_auth_config_show!(form_values: auth_params)
        return render :show, status: :unprocessable_entity
      end
    end

    result = Projects::UpdateService.new(
      project: @project,
      params: auth_params,
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
      prepare_auth_config_show!(form_values: permitted_auth_params)
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
      payload = result.data[:reveal_payload]
      cache_failed = result.data[:cache_failed]

      if json_request?
        disable_secret_response_cache!
        render json: payload, status: :created
      elsif plain_html_request? || request.format.turbo_stream?
        # Render in-band for all browser formats (plain HTML and Turbo).
        # The service never writes to the shared reveal cache, so no cache
        # consumption step is needed here.
        # Trade-off: skips PRG pattern. The button uses data-turbo=false
        # (native confirm) and no-store prevents cache restore. A redirect
        # would require shared cache (the security regression this avoids)
        # or session secret storage (forbidden by policy).
        flash.now[:success] = "Client Secret이 재발급되었습니다. 기존 Secret은 즉시 무효화됩니다."
        prepare_auth_config_show!(reveal_payload: payload)
        disable_secret_response_cache!
        render :show, formats: [ :html ]
      else
        # Non-browser, non-JSON fallback.
        flash[:error] = "Client Secret이 재발급되었지만 표시할 수 없습니다. 잠시 후 다시 재발급하세요."
        redirect_to organization_project_auth_config_path(@organization.slug, @project.slug), status: :see_other
      end
    else
      return render json: { errors: [ result.error ] }, status: :unprocessable_entity if json_request?

      @errors = [ result.error ]
      prepare_auth_config_show!
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
      normalized[:redirect_uris] = normalize_auth_config_uri_values(permitted[:redirect_uris])
    end
    if permitted.key?(:post_logout_redirect_uris)
      normalized[:post_logout_redirect_uris] = normalize_auth_config_uri_values(permitted[:post_logout_redirect_uris])
    end
    normalized
  end

  def render_auth_config_not_found
    return render json: { error: "Not found" }, status: :not_found if json_request?

    respond_to do |format|
      format.html { render "projects/not_found", status: :not_found }
      format.json { render json: { error: "Not found" }, status: :not_found }
    end
  end

  def pkce_redirect_uri_errors(uris)
    Array(uris).compact_blank.flat_map do |uri|
      errors = []
      begin
        parsed = URI.parse(uri)
        errors << "OAuth Redirect URI에 fragment(#)를 포함할 수 없습니다: #{uri}" if parsed.fragment.present?
        if parsed.host.blank?
          errors << "OAuth Redirect URI에 유효한 호스트가 없습니다: #{uri}"
        else
          localhost = parsed.scheme == "http" && %w[localhost 127.0.0.1 [::1]].include?(parsed.host)
          errors << "OAuth Redirect URI는 HTTPS를 사용해야 합니다 (localhost 제외): #{uri}" unless parsed.scheme == "https" || localhost
        end
      rescue URI::InvalidURIError
        errors << "유효하지 않은 URI 형식입니다: #{uri}"
      end
      errors
    end
  end

  def json_request?
    request.format.json? || default_json_request?
  end

  def plain_html_request?
    # Note: Mime[:turbo_stream]#html? returns true because the turbo_stream
    # mime type ends with `.html`. Compare the format symbol so the in-band
    # rotated-secret render stays scoped to genuinely plain text/html
    # responses only.
    request.format.symbol == :html && !default_json_request?
  end
end
