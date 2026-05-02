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
        cache_persisted = begin
          ProjectApiKeys::RevealCache.write(@project, project_api_key: key, token: token).present?
        rescue StandardError => e
          Rails.logger.error("Project API Key reveal cache write failed for project #{@project.id}: #{e.class}: #{e.message}")
          false
        end

        if cache_persisted
          flash[:success] = "PAK가 발급되었습니다."
          redirect_to organization_project_auth_config_path(@organization.slug, @project.slug), status: :see_other
        elsif plain_html_request?
          # Cache could not persist the PAK plaintext. Render the auth config
          # page in-band with the freshly issued PAK so the operator can copy
          # it once; the key remains active in the DB so the operator stays in
          # control of revoke vs retry. Restrict to pure HTML so a Turbo Stream
          # or other negotiated format cannot receive a secret-bearing body
          # outside the no-store page lifecycle.
          render_pak_in_band_fallback(key, token)
        else
          # Non-HTML browser format (turbo_stream). Fail closed and let the
          # operator revoke + reissue rather than streaming the plaintext
          # through a path we cannot fully gate as no-store.
          flash[:error] = "표시 캐시 저장에 실패했습니다. 발급된 PAK는 목록에서 폐기 후 다시 발급해주세요."
          redirect_to organization_project_auth_config_path(@organization.slug, @project.slug), status: :see_other
        end
      else
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

    ProjectApiKeys::RevealCache.delete_if_matches(@project, project_api_key_id: @project_api_key.id)

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

  def render_pak_in_band_fallback(key, token)
    @auth_config = @project.project_auth_config
    unless @auth_config
      flash[:error] = "인증 설정이 없어 PAK를 표시할 수 없습니다. 발급된 PAK는 목록에서 폐기 후 다시 발급해주세요."
      redirect_to organization_project_auth_config_path(@organization.slug, @project.slug), status: :see_other
      return
    end

    # A previous reveal may have populated the per-project cache with a stale
    # payload pointing at a now-superseded PAK. Drop that entry first so a
    # later auth-config GET cannot resurface the old token in place of the
    # freshly issued one. If delete fails, attempt to overwrite the entry with
    # the fresh payload — that still removes the stale value from any future
    # read. If both calls fail, fail closed and tell the operator to revoke
    # and reissue rather than leaving a stale plaintext readable from cache.
    cache_reconciled = reconcile_pak_reveal_cache(key, token)
    unless cache_reconciled
      flash[:error] = "표시 캐시 정리에 실패했습니다. 발급된 PAK는 목록에서 폐기 후 다시 발급해주세요."
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

  # Returns true when the per-project reveal cache no longer holds a stale
  # token. The contract: after this method returns true, a later GET must not
  # surface a different PAK than the one in the in-band response. The method
  # treats only two cache states as safe: (a) the cache holds NO secret entries
  # at all, or (b) the cache holds the freshly issued PAK and only that PAK.
  # A malformed stale payload that hides under `.dig` would otherwise fool a
  # naive blank? check, so we verify both shapes explicitly.
  def reconcile_pak_reveal_cache(key, token)
    delete_succeeded = begin
      ProjectApiKeys::RevealCache.delete(@project)
      true
    rescue StandardError => delete_error
      Rails.logger.error("Project API Key reveal cache delete failed for project #{@project.id}: #{delete_error.class}: #{delete_error.message}")
      false
    end

    return true if delete_succeeded && pak_reveal_cache_truly_empty?

    # Cache may still hold a stale or malformed entry. Overwrite with the
    # fresh payload and verify the read-back now matches the issued PAK.
    written = begin
      ProjectApiKeys::RevealCache.write(@project, project_api_key: key, token: token).present?
    rescue StandardError => write_error
      Rails.logger.error("Project API Key reveal cache reconcile-write failed for project #{@project.id}: #{write_error.class}: #{write_error.message}")
      false
    end
    unless written
      Rails.logger.error("Project API Key reveal cache reconcile-write returned a falsy result for project #{@project.id}")
      return false
    end

    pak_reveal_cache_matches?(key)
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
