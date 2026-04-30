class ProjectApiKeysController < ApplicationController
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
        reveal_payload = ProjectApiKeys::RevealCache.reveal_payload(@project, project_api_key: key, token: token)
        cache_persisted = ProjectApiKeys::RevealCache.write(@project, project_api_key: key, token: token).present?
        persist_reveal_fallback!(reveal_payload) unless cache_persisted
        clear_reveal_fallback! if cache_persisted
        flash[:success] = "PAK가 발급되었습니다."
        flash[:warning] = "공유 캐시 저장에 실패해 이 브라우저 세션에서만 다시 볼 수 있습니다." unless cache_persisted
        redirect_to organization_project_auth_config_path(@organization.slug, @project.slug), status: :see_other
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
    clear_reveal_fallback!(project_api_key_id: @project_api_key.id)

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

  def persist_reveal_fallback!(payload)
    session[:project_api_key_reveal_fallbacks] ||= {}
    session[:project_api_key_reveal_fallbacks][@project.id.to_s] = payload
  end

  def clear_reveal_fallback!(project_api_key_id: nil)
    fallbacks = session[:project_api_key_reveal_fallbacks]
    return unless fallbacks.is_a?(Hash)

    payload = fallbacks[@project.id.to_s]
    return unless payload.is_a?(Hash)

    revealed_key_id = payload.dig("secrets", "project_api_key", "project_api_key_id")
    return if project_api_key_id.present? && revealed_key_id.to_i != project_api_key_id.to_i

    fallbacks.delete(@project.id.to_s)
  end
end
