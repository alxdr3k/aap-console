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
      elsif !cache_failed
        flash[:warning] = "Client Secret이 재발급되었습니다. 기존 Secret은 즉시 무효화됩니다."
        redirect_to organization_project_auth_config_path(@organization.slug, @project.slug), status: :see_other
      elsif plain_html_request?
        # Cache could not persist the rotated secret. Render the page in-band
        # with the fresh secret so the operator can copy it once; redirecting
        # would discard the value because the show action reads from the cache.
        # Restrict to pure HTML so a Turbo Stream or other negotiated format
        # cannot receive a secret-bearing response body that intermediaries
        # may handle outside the no-store page lifecycle.
        flash.now[:warning] = "Client Secret이 재발급되었지만 표시 캐시 저장에 실패했습니다. 이 화면을 떠나기 전에 즉시 복사하세요."
        prepare_auth_config_show!(reveal_payload: payload)
        disable_secret_response_cache!
        render :show, formats: [ :html ]
      else
        # Non-HTML browser format (e.g. text/vnd.turbo-stream.html). Fail closed
        # rather than streaming the rotated secret through a non-no-store path.
        flash[:error] = "Client Secret이 재발급되었지만 표시 캐시 저장에 실패했습니다. 잠시 후 다시 재발급하세요."
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
