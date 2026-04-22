class OrganizationsController < ApplicationController
  before_action :set_organization, only: [:show, :update, :destroy]
  before_action -> { authorize_org!(@organization) }, only: [:show]
  before_action -> { authorize_org!(@organization, minimum_role: :admin) }, only: [:update]
  before_action :require_super_admin!, only: [:create, :destroy]

  def index
    @organizations = current_authorization.organizations
    render json: @organizations
  end

  def show
    render json: @organization
  end

  def new
    @organization = Organization.new
    render json: {}
  end

  def create
    result = Organizations::CreateService.new(
      params: organization_params,
      current_user_sub: Current.user_sub
    ).call

    if result.success?
      redirect_to organization_path(result.data.slug), status: :see_other
    else
      render json: { errors: [result.error] }, status: :unprocessable_entity
    end
  end

  def update
    if @organization.update(organization_params)
      AuditLog.create!(
        organization: @organization,
        user_sub: Current.user_sub,
        action: "org.update",
        resource_type: "Organization",
        resource_id: @organization.id.to_s,
        details: { name: @organization.name }
      )
      redirect_to organization_path(@organization.slug), status: :see_other
    else
      render json: { errors: @organization.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    result = Organizations::DestroyService.new(
      organization: @organization,
      current_user_sub: Current.user_sub
    ).call

    if result.success?
      redirect_to organizations_path, status: :see_other
    else
      render json: { errors: [result.error] }, status: :unprocessable_entity
    end
  end

  private

  def set_organization
    @organization = Organization.find_by!(slug: params[:slug])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Not found" }, status: :not_found
  end

  def organization_params
    params.require(:organization).permit(:name, :description)
  end
end
