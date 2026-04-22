class ProjectsController < ApplicationController
  before_action :set_organization
  before_action -> { authorize_org!(@organization) }, only: [:index]
  before_action -> { authorize_org!(@organization, minimum_role: :admin) }, only: [:create, :destroy]
  before_action :set_project, only: [:show, :update, :destroy]
  before_action -> { authorize_project!(@project) }, only: [:show]
  before_action -> { authorize_project!(@project, minimum_role: :write) }, only: [:update]

  def index
    projects = current_authorization.accessible_projects(@organization)
    render json: projects
  end

  def create
    result = Projects::CreateService.new(
      organization: @organization,
      params: project_params,
      current_user_sub: Current.user_sub
    ).call

    if result.success?
      project = result.data
      provisioning_job = project.provisioning_jobs.last
      redirect_to provisioning_job_path(provisioning_job), status: :see_other
    else
      render json: { errors: [result.error] }, status: :unprocessable_entity
    end
  end

  def show
    render json: @project
  end

  def update
    if @project.update(project_update_params)
      AuditLog.create!(
        organization: @organization,
        project: @project,
        user_sub: Current.user_sub,
        action: "project.update",
        resource_type: "Project",
        resource_id: @project.id.to_s,
        details: { name: @project.name }
      )
      render json: @project
    else
      render json: { errors: @project.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    result = Projects::DestroyService.new(
      project: @project,
      current_user_sub: Current.user_sub
    ).call

    if result.success?
      project = result.data
      provisioning_job = project.provisioning_jobs.where(operation: "delete").last
      redirect_to provisioning_job_path(provisioning_job), status: :see_other
    else
      render json: { errors: [result.error] }, status: :unprocessable_entity
    end
  end

  private

  def set_organization
    @organization = Organization.find_by!(slug: params[:organization_slug])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Not found" }, status: :not_found
  end

  def set_project
    @project = @organization.projects.find_by!(slug: params[:slug])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Not found" }, status: :not_found
  end

  def project_params
    params.require(:project).permit(:name, :description, :auth_type, :s3_retention_days, models: [])
  end

  def project_update_params
    params.require(:project).permit(:name, :description)
  end
end
