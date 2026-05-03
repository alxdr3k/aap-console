class ProjectApiKeysController < ApplicationController
  include AuthConfigShowState

  before_action :set_organization
  before_action :set_project
  before_action -> { authorize_project!(@project) }, only: [ :index ]
  before_action -> { authorize_project!(@project, minimum_role: :write) }, only: [ :create, :destroy ]
  before_action :set_project_api_key, only: [ :destroy ]

  def index
    if browser_request?
      redirect_to organization_project_auth_config_path(@organization.slug, @project.slug), status: :see_other
    else
      render json: @project.project_api_keys.order(created_at: :desc).map { |key| serialize_key(key) }
    end
  end

  def create
    result = ProjectApiKeys::IssueService.new(
      project: @project,
      name: project_api_key_params[:name],
      current_user_sub: Current.user_sub
    ).call

    if result.success?
      key = result.data.fetch(:project_api_key)
      token = result.data.fetch(:token)

      if browser_request?
        cache_state = stage_pak_reveal_cache(key, token)
        handle_pak_cache_state(cache_state, key, token)
      else
        disable_secret_response_cache!
        render json: serialize_key(key).merge(token: token), status: :created
      end
    else
      if browser_request?
        flash[:error] = result.error
        redirect_to organization_project_auth_config_path(@organization.slug, @project.slug), status: :see_other
      else
        render json: { errors: [ result.error ] }, status: :unprocessable_entity
      end
    end
  end

  def destroy
    result = ProjectApiKeys::RevokeService.new(
      project_api_key: @project_api_key,
      current_user_sub: Current.user_sub
    ).call

    # Serialize the read-then-delete with the create path's locked cache
    # writers so a revoke cannot interleave with a concurrent issue's
    # successful write and erase a newer reveal that the create path just
    # cached for another operator.
    @project.with_lock do
      ProjectApiKeys::RevealCache.delete_if_matches(@project, project_api_key_id: @project_api_key.id)
    end

    if browser_request?
      flash[:success] = "PAK를 폐기했습니다."
      redirect_to organization_project_auth_config_path(@organization.slug, @project.slug), status: :see_other
    else
      render json: serialize_key(result.data)
    end
  end

  private

  def set_organization
    @organization = Organization.find_by!(slug: params[:organization_slug])
  rescue ActiveRecord::RecordNotFound
    return render json: { error: "Not found" }, status: :not_found unless browser_request?

    render "projects/not_found", status: :not_found
  end

  def set_project
    @project = @organization.projects.find_by!(slug: params[:project_slug])
  rescue ActiveRecord::RecordNotFound
    return render json: { error: "Not found" }, status: :not_found unless browser_request?

    render "projects/not_found", status: :not_found
  end

  def set_project_api_key
    @project_api_key = @project.project_api_keys.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    return render json: { error: "Not found" }, status: :not_found unless browser_request?

    render "projects/not_found", status: :not_found
  end

  def project_api_key_params
    params.require(:project_api_key).permit(:name)
  end

  def serialize_key(project_api_key)
    {
      id: project_api_key.id,
      name: project_api_key.name,
      token_prefix: project_api_key.token_prefix,
      last_used_at: project_api_key.last_used_at,
      revoked_at: project_api_key.revoked_at,
      created_at: project_api_key.created_at
    }
  end

  def browser_request?
    (request.format.html? || request.format.turbo_stream?) && !default_json_request?
  end

  def plain_html_request?
    # Note: Mime[:turbo_stream]#html? returns true because the turbo_stream
    # mime type ends with `.html`. Compare the format symbol to keep the
    # in-band reveal scoped to genuinely plain text/html responses only.
    request.format.symbol == :html && !default_json_request?
  end

  # Serialize all per-project reveal cache mutations (the primary write AND
  # any fallback reconcile) under the same project row lock. Without this,
  # the lock-protected fallback could still race with an unlocked successful
  # write from a concurrent request and clobber the newer reveal. Returns one
  # of: :persisted (cache holds our key), :superseded_by_newer (cache holds a
  # newer concurrent reveal — leave it), :empty_render_in_band (cache is
  # empty, render the secret in-band so the operator can copy it once), or
  # :fail_closed (cache state is unknown/stale and we cannot guarantee a
  # safe read on the next GET).
  def stage_pak_reveal_cache(key, token)
    @project.with_lock do
      current = read_pak_reveal_payload_safely

      if current.is_a?(Hash) && current["project_api_key_id"].to_i > key.id.to_i
        Rails.logger.info(
          "[ProjectApiKeysController] cache holds newer PAK reveal " \
          "(id=#{current["project_api_key_id"]}) than current issuance (id=#{key.id}); leaving newer reveal in place"
        )
        next :superseded_by_newer
      end

      begin
        next :persisted if ProjectApiKeys::RevealCache.write(@project, project_api_key: key, token: token).present?
      rescue StandardError => write_error
        Rails.logger.error("Project API Key reveal cache write failed for project #{@project.id}: #{write_error.class}: #{write_error.message}")
      end

      delete_succeeded = begin
        ProjectApiKeys::RevealCache.delete(@project)
        true
      rescue StandardError => delete_error
        Rails.logger.error("Project API Key reveal cache delete failed for project #{@project.id}: #{delete_error.class}: #{delete_error.message}")
        false
      end

      next :empty_render_in_band if delete_succeeded && pak_reveal_cache_truly_empty?

      retry_written = begin
        ProjectApiKeys::RevealCache.write(@project, project_api_key: key, token: token).present?
      rescue StandardError => retry_error
        Rails.logger.error("Project API Key reveal cache reconcile-write failed for project #{@project.id}: #{retry_error.class}: #{retry_error.message}")
        false
      end

      next :persisted if retry_written && pak_reveal_cache_matches?(key)

      :fail_closed
    end
  end

  def handle_pak_cache_state(state, key, token)
    case state
    when :persisted
      if plain_html_request?
        # Render in-band rather than redirecting through the shared reveal cache.
        # A concurrent issue can overwrite the cache between our write and the
        # redirect GET, causing the wrong operator's plaintext PAK to be shown.
        render_pak_in_band(key, token)
      else
        flash[:success] = "PAK가 발급되었습니다."
        redirect_to organization_project_auth_config_path(@organization.slug, @project.slug), status: :see_other
      end
    when :superseded_by_newer
      if plain_html_request?
        # Render our own PAK in-band; leave the newer cached reveal untouched.
        render_pak_in_band_fallback(key, token)
      else
        # For non-plain-HTML paths (Turbo), purge the cached reveal before
        # redirecting so auth_configs#show cannot surface another operator's
        # plaintext PAK to this request.
        begin
          ProjectApiKeys::RevealCache.delete(@project)
        rescue StandardError => e
          Rails.logger.error("PAK reveal cache purge failed before superseded redirect project=#{@project.id}: #{e.class}: #{e.message}")
        end
        flash[:error] = "동시에 다른 PAK가 발급되어 표시 캐시에 자리가 없습니다. 발급된 PAK는 목록에서 폐기 후 다시 발급해주세요."
        redirect_to organization_project_auth_config_path(@organization.slug, @project.slug), status: :see_other
      end
    when :empty_render_in_band
      if plain_html_request?
        render_pak_in_band_fallback(key, token)
      else
        # Non-HTML browser format (turbo_stream). Fail closed and let the
        # operator revoke + reissue rather than streaming the plaintext
        # through a path we cannot fully gate as no-store.
        flash[:error] = "표시 캐시 저장에 실패했습니다. 발급된 PAK는 목록에서 폐기 후 다시 발급해주세요."
        redirect_to organization_project_auth_config_path(@organization.slug, @project.slug), status: :see_other
      end
    when :fail_closed
      flash[:error] = "표시 캐시 정리에 실패했습니다. 발급된 PAK는 목록에서 폐기 후 다시 발급해주세요."
      redirect_to organization_project_auth_config_path(@organization.slug, @project.slug), status: :see_other
    end
  end

  def render_pak_in_band(key, token)
    @auth_config = @project.project_auth_config
    unless @auth_config
      flash[:error] = "인증 설정이 없어 PAK를 표시할 수 없습니다. 발급된 PAK는 목록에서 폐기 후 다시 발급해주세요."
      redirect_to organization_project_auth_config_path(@organization.slug, @project.slug), status: :see_other
      return
    end

    payload = ProjectApiKeys::RevealCache
      .reveal_payload(@project, project_api_key: key, token: token)
      .merge("expires_at" => Time.current.iso8601(6))

    flash.now[:success] = "PAK가 발급되었습니다."
    prepare_auth_config_show!(pak_reveal_payload: payload)
    disable_secret_response_cache!
    render template: "auth_configs/show", formats: [ :html ]
  end

  def render_pak_in_band_fallback(key, token)
    @auth_config = @project.project_auth_config
    unless @auth_config
      flash[:error] = "인증 설정이 없어 PAK를 표시할 수 없습니다. 발급된 PAK는 목록에서 폐기 후 다시 발급해주세요."
      redirect_to organization_project_auth_config_path(@organization.slug, @project.slug), status: :see_other
      return
    end

    payload = ProjectApiKeys::RevealCache
      .reveal_payload(@project, project_api_key: key, token: token)
      .merge("cache_failed" => true, "expires_at" => Time.current.iso8601(6))

    flash.now[:warning] = "표시 캐시 저장에 실패했습니다. 이 화면을 떠나기 전에 즉시 PAK 평문을 복사하세요."
    prepare_auth_config_show!(pak_reveal_payload: payload)
    disable_secret_response_cache!
    render template: "auth_configs/show", formats: [ :html ]
  end

  def read_pak_reveal_payload_safely
    ProjectApiKeys::RevealCache.read(@project).dig("secrets", "project_api_key")
  rescue StandardError => e
    Rails.logger.error("Project API Key reveal cache read failed for project #{@project.id}: #{e.class}: #{e.message}")
    nil
  end

  def pak_reveal_cache_truly_empty?
    secrets = ProjectApiKeys::RevealCache.read(@project).fetch("secrets", {})
    secrets.is_a?(Hash) && secrets.empty?
  rescue StandardError => e
    Rails.logger.error("Project API Key reveal cache read-back failed for project #{@project.id}: #{e.class}: #{e.message}")
    false
  end

  def pak_reveal_cache_matches?(key)
    revealed = ProjectApiKeys::RevealCache.read(@project).dig("secrets", "project_api_key")
    revealed.is_a?(Hash) && revealed["project_api_key_id"].to_i == key.id.to_i
  rescue StandardError => e
    Rails.logger.error("Project API Key reveal cache match check failed for project #{@project.id}: #{e.class}: #{e.message}")
    false
  end
end
