class OrganizationsController < ApplicationController
  before_action :set_organization, only: [ :show, :update, :destroy ]
  before_action -> { authorize_org!(@organization) }, only: [ :show ]
  before_action -> { authorize_org!(@organization, minimum_role: :admin) }, only: [ :update ]
  before_action :require_super_admin!, only: [ :new, :create, :destroy ]

  def index
    @organizations = current_authorization.organizations.order(:name)

    respond_to do |format|
      format.html
      format.json { render json: @organizations }
    end
  end

  def show
    @projects = current_authorization.accessible_projects(@organization).order(:name)
    @member_counts = @organization.org_memberships.group(:role).count

    respond_to do |format|
      format.html
      format.json { render json: @organization }
    end
  end

  def new
    @organization = Organization.new

    respond_to do |format|
      format.html
      format.json { render json: {} }
    end
  end

  def create
    result = Organizations::CreateService.new(
      params: organization_params,
      current_user_sub: Current.user_sub
    ).call

    if result.success?
      flash[:success] = "Organization이 생성되었습니다."
      redirect_to organization_path(result.data.slug), status: :see_other
    else
      @organization = Organization.new(organization_params.except(:initial_admin_user_sub))
      @errors = [ result.error ]

      respond_to do |format|
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: { errors: @errors }, status: :unprocessable_entity }
      end
    end
  end

  def update
    result = Organizations::UpdateService.new(
      organization: @organization,
      params: organization_params,
      current_user_sub: Current.user_sub
    ).call

    if result.success?
      flash[:success] = "변경 사항이 저장되었습니다."
      redirect_to organization_path(@organization.slug), status: :see_other
    else
      render json: { errors: [ result.error ] }, status: :unprocessable_entity
    end
  end

  def destroy
    result = Organizations::DestroyService.new(
      organization: @organization,
      current_user_sub: Current.user_sub
    ).call

    if result.success?
      flash[:success] = "Organization 삭제를 시작했습니다."
      redirect_to organizations_path, status: :see_other
    else
      render json: { errors: [ result.error ] }, status: :unprocessable_entity
    end
  end

  private

  def set_organization
    @organization = Organization.find_by!(slug: params[:slug])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Not found" }, status: :not_found
  end

  def organization_params
    params.require(:organization).permit(:name, :description, :initial_admin_user_sub)
  end
end
