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
        ProjectApiKeys::RevealCache.write(@project, project_api_key: key, token: token)
        flash[:success] = "PAK가 발급되었습니다."
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

    ProjectApiKeys::RevealCache.delete(@project)

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
    request.format.html? && !default_json_request?
  end
end
