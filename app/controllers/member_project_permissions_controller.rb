class MemberProjectPermissionsController < ApplicationController
  before_action :prefer_json_for_default_requests
  before_action :set_organization
  before_action -> { authorize_org!(@organization, minimum_role: :admin) }
  before_action :set_membership
  before_action :ensure_project_permissions_supported!
  before_action :set_project, only: [ :update, :destroy ]
  before_action :set_permission, only: [ :update, :destroy ]

  def create
    project = @organization.projects.where.not(status: :deleted).find_by!(slug: permission_params[:project_slug])
    permission = @membership.project_permissions.find_or_initialize_by(project: project)
    created = permission.new_record?
    permission.role = permission_params[:role]

    ActiveRecord::Base.transaction do
      permission.save!
      audit_permission!(created ? "member.project_permission.grant" : "member.project_permission.update", permission)
    end

    respond_to do |format|
      format.json { render json: serialize_permission(permission), status: created ? :created : :ok }
      format.html do
        flash[:success] = "Project 권한이 저장되었습니다."
        redirect_to organization_members_path(@organization.slug), status: :see_other
      end
    end
  rescue ActiveRecord::RecordInvalid => e
    render_permission_errors(e.record.errors.full_messages)
  rescue ActiveRecord::RecordNotFound
    render_permission_error("Project not found", :not_found)
  end

  def update
    @permission.role = permission_params[:role]

    ActiveRecord::Base.transaction do
      @permission.save!
      audit_permission!("member.project_permission.update", @permission)
    end

    respond_to do |format|
      format.json { render json: serialize_permission(@permission) }
      format.html do
        flash[:success] = "Project 권한이 변경되었습니다."
        redirect_to organization_members_path(@organization.slug), status: :see_other
      end
    end
  rescue ActiveRecord::RecordInvalid => e
    render_permission_errors(e.record.errors.full_messages)
  end

  def destroy
    ActiveRecord::Base.transaction do
      @permission.destroy!
      audit_permission!("member.project_permission.revoke", @permission)
    end

    respond_to do |format|
      format.json { render json: { message: "Project permission revoked" } }
      format.html do
        flash[:success] = "Project 권한이 제거되었습니다."
        redirect_to organization_members_path(@organization.slug), status: :see_other
      end
    end
  end

  private

  def permission_params
    @permission_params ||= begin
      permission = parameter_hash(params.require(:project_permission))

      {
        project_slug: permission[:project_slug],
        role: permission[:role]
      }.with_indifferent_access
    end
  end

  def parameter_hash(value)
    value = value.to_unsafe_h if value.respond_to?(:to_unsafe_h)
    value = value.to_h if value.respond_to?(:to_h)
    return {}.with_indifferent_access unless value.is_a?(Hash)

    value.with_indifferent_access
  end

  def set_organization
    @organization = Organization.find_by!(slug: params[:organization_slug])
  rescue ActiveRecord::RecordNotFound
    respond_to do |format|
      format.json { render json: { error: "Not found" }, status: :not_found }
      format.html { render "organizations/not_found", status: :not_found }
    end
  end

  def set_membership
    @membership = @organization.org_memberships.find_by!(user_sub: params[:user_sub])
  rescue ActiveRecord::RecordNotFound
    render_permission_error("Member not found", :not_found)
  end

  def set_project
    @project = @organization.projects.where.not(status: :deleted).find_by!(slug: params[:project_slug])
  rescue ActiveRecord::RecordNotFound
    render_permission_error("Project not found", :not_found)
  end

  def set_permission
    @permission = @membership.project_permissions.find_by!(project: @project)
  rescue ActiveRecord::RecordNotFound
    render_permission_error("Project permission not found", :not_found)
  end

  def ensure_project_permissions_supported!
    return unless @membership.admin?

    render_permission_error("Admin members have implicit access to every project", :unprocessable_entity)
  end

  def audit_permission!(action, permission)
    AuditLog.create!(
      organization: @organization,
      project: permission.project,
      user_sub: Current.user_sub,
      action: action,
      resource_type: "ProjectPermission",
      resource_id: permission.id.to_s,
      details: {
        member_user_sub: @membership.user_sub,
        project_slug: permission.project.slug,
        role: permission.role
      }
    )
  end

  def serialize_permission(permission)
    {
      id: permission.id,
      member_user_sub: @membership.user_sub,
      project_slug: permission.project.slug,
      project_name: permission.project.name,
      role: permission.role
    }
  end

  def render_permission_errors(errors)
    respond_to do |format|
      format.json { render json: { errors: Array(errors) }, status: :unprocessable_entity }
      format.html { redirect_with_permission_error(Array(errors).to_sentence, :unprocessable_entity) }
    end
  end

  def render_permission_error(error, status)
    respond_to do |format|
      format.json { render json: { error: error }, status: status }
      format.html { redirect_with_permission_error(error, status) }
    end
  end

  def redirect_with_permission_error(error, _status)
    flash[:error] = error
    redirect_to organization_members_path(@organization.slug), status: :see_other
  end
end
