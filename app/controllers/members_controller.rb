class MembersController < ApplicationController
  before_action :prefer_json_for_default_requests
  before_action :set_organization
  before_action -> { authorize_org!(@organization) }, only: [ :index ]
  before_action -> { authorize_org!(@organization, minimum_role: :admin) }, only: [ :create, :update, :destroy ]
  before_action :set_membership, only: [ :update, :destroy ]

  def index
    prepare_members_index

    respond_to do |format|
      format.json do
        render json: @memberships.map { |membership| serialize_membership(membership, @users_by_sub[membership.user_sub]) }
      end
      format.html
    end
  rescue BaseClient::ApiError
    @memberships = membership_scope
    @projects = active_projects
    @users_by_sub = {}

    respond_to do |format|
      format.json { render json: { error: "Keycloak user lookup failed" }, status: :service_unavailable }
      format.html do
        @member_errors = [ "Keycloak user lookup failed" ]
        render :index, status: :service_unavailable
      end
    end
  end

  def create
    attrs = member_params
    created_keycloak_user_sub = nil
    user_sub = resolve_member_user_sub(attrs) { |created_sub| created_keycloak_user_sub = created_sub }
    role = attrs[:role]

    if user_sub.blank?
      return render_member_errors([ "user_sub or email can't be blank" ], :unprocessable_entity)
    end

    membership = @organization.org_memberships.build(
      user_sub: user_sub,
      role: role,
      invited_at: Time.current
    )

    begin
      ActiveRecord::Base.transaction do
        membership.save!
        create_project_permissions!(membership, member_project_permission_specs)

        AuditLog.create!(
          organization: @organization,
          user_sub: Current.user_sub,
          action: "member.add",
          resource_type: "OrgMembership",
          resource_id: membership.id.to_s,
          details: {
            added_user_sub: user_sub,
            role: role,
            preassigned: attrs[:email].present? && attrs[:user_sub].blank?,
            project_permissions: member_project_permission_specs
          }
        )
      end

      respond_to do |format|
        format.json { render json: serialize_membership(membership.reload), status: :created }
        format.html do
          flash[:success] = "멤버가 추가되었습니다."
          redirect_to organization_members_path(@organization.slug), status: :see_other
        end
      end
    rescue ActiveRecord::RecordInvalid => e
      compensate_keycloak_user(created_keycloak_user_sub)
      render_member_errors(e.record.errors.full_messages, :unprocessable_entity)
    end
  rescue BaseClient::NotFoundError
    render_member_errors([ "User not found" ], :unprocessable_entity)
  rescue BaseClient::ApiError
    render_member_error("Keycloak user lookup failed", :service_unavailable)
  rescue ActiveRecord::RecordNotFound
    compensate_keycloak_user(created_keycloak_user_sub)
    render_member_error("Project not found", :not_found)
  end

  def update
    new_role = member_params[:role]

    @organization.with_lock do
      if demoting_last_admin?(@membership, new_role)
        return render_member_error("Cannot demote the last admin of this organization", :unprocessable_entity)
      end

      if @membership.update(role: new_role)
        cleared_project_permissions_count = clear_project_permissions_for_admin!(@membership)
        AuditLog.create!(
          organization: @organization,
          user_sub: Current.user_sub,
          action: "member.update",
          resource_type: "OrgMembership",
          resource_id: @membership.id.to_s,
          details: {
            user_sub: @membership.user_sub,
            role: @membership.role,
            cleared_project_permissions_count: cleared_project_permissions_count
          }
        )
        respond_to do |format|
          format.json { render json: serialize_membership(@membership.reload) }
          format.html do
            flash[:success] = "멤버 권한이 변경되었습니다."
            redirect_to organization_members_path(@organization.slug), status: :see_other
          end
        end
      else
        render_member_errors(@membership.errors.full_messages, :unprocessable_entity)
      end
    end
  end

  def destroy
    @organization.with_lock do
      if removing_last_admin?(@membership)
        return render_member_error("Cannot remove the last admin of this organization", :unprocessable_entity)
      end

      @membership.destroy!
      AuditLog.create!(
        organization: @organization,
        user_sub: Current.user_sub,
        action: "member.remove",
        resource_type: "OrgMembership",
        resource_id: @membership.id.to_s,
        details: { removed_user_sub: @membership.user_sub }
      )
      respond_to do |format|
        format.json { render json: { message: "Member removed" } }
        format.html do
          flash[:success] = "멤버가 제거되었습니다."
          redirect_to organization_members_path(@organization.slug), status: :see_other
        end
      end
    end
  end

  private

  def prefer_json_for_default_requests
    request.format = :json if default_json_request?
  end

  def keycloak_client
    @keycloak_client ||= KeycloakClient.new
  end

  def member_params
    @member_params ||= begin
      member = parameter_hash(params.require(:member))
      project_permissions = member[:project_permissions]
      project_permissions = project_permissions.values if project_permissions.is_a?(Hash)

      {
        user_sub: member[:user_sub],
        email: member[:email],
        role: member[:role],
        project_permissions: Array(project_permissions).filter_map do |permission|
          permission = parameter_hash(permission)
          next if permission[:project_slug].blank?

          {
            project_slug: permission[:project_slug],
            role: permission[:role]
          }
        end
      }.with_indifferent_access
    end
  end

  def parameter_hash(value)
    value = value.to_unsafe_h if value.respond_to?(:to_unsafe_h)
    value = value.to_h if value.respond_to?(:to_h)
    return {}.with_indifferent_access unless value.is_a?(Hash)

    value.with_indifferent_access
  end

  def member_project_permission_specs
    Array(member_params[:project_permissions]).map do |permission|
      permission.symbolize_keys.slice(:project_slug, :role)
    end
  end

  def resolve_member_user_sub(attrs)
    user_sub = attrs[:user_sub].to_s.strip
    email = attrs[:email].to_s.strip

    if user_sub.present?
      keycloak_client.get_user(user_sub: user_sub)
      user_sub
    elsif email.present?
      created_user_sub = keycloak_client.create_user(email: email)["id"]
      yield created_user_sub if block_given?
      created_user_sub
    end
  end

  def compensate_keycloak_user(user_sub)
    return if user_sub.blank?

    keycloak_client.delete_user(user_sub: user_sub)
  rescue BaseClient::ApiError => e
    Rails.logger.error(
      "[MembersController] Failed to compensate Keycloak user #{user_sub} " \
      "after member create failure: #{e.class}: #{e.message}"
    )
  end

  def create_project_permissions!(membership, permission_specs)
    return if permission_specs.blank?

    if membership.admin?
      membership.errors.add(:project_permissions, "are implicit for admin members")
      raise ActiveRecord::RecordInvalid.new(membership)
    end

    permission_specs.each do |permission_spec|
      project = @organization.projects.where.not(status: :deleted).find_by!(slug: permission_spec[:project_slug])
      membership.project_permissions.create!(project: project, role: permission_spec[:role])
    end
  end

  def prepare_members_index
    @memberships = membership_scope
    @projects = active_projects
    @users_by_sub = keycloak_client.get_users_by_ids(user_subs: @memberships.map(&:user_sub))
  end

  def membership_scope
    @organization.org_memberships.includes(project_permissions: :project).order(:created_at)
  end

  def active_projects
    @organization.projects.where.not(status: :deleted).order(:name)
  end

  def render_member_errors(errors, status)
    respond_to do |format|
      format.json { render json: { errors: Array(errors) }, status: status }
      format.html { render_members_index_with_errors(Array(errors), status) }
    end
  end

  def render_member_error(error, status)
    respond_to do |format|
      format.json { render json: { error: error }, status: status }
      format.html { render_members_index_with_errors([ error ], status) }
    end
  end

  def render_members_index_with_errors(errors, status)
    @member_errors = errors
    @memberships = membership_scope
    @projects = active_projects
    @users_by_sub = {}
    render :index, status: status
  end

  def clear_project_permissions_for_admin!(membership)
    return 0 unless membership.admin?

    count = membership.project_permissions.count
    membership.project_permissions.destroy_all
    count
  end

  def serialize_membership(membership, keycloak_user = nil)
    {
      id: membership.id,
      user_sub: membership.user_sub,
      role: membership.role,
      invited_at: membership.invited_at,
      joined_at: membership.joined_at,
      user: keycloak_user,
      project_permissions: membership.project_permissions.map { |permission| serialize_project_permission(permission) }
    }
  end

  def serialize_project_permission(permission)
    {
      id: permission.id,
      project_slug: permission.project.slug,
      project_name: permission.project.name,
      role: permission.role
    }
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
    respond_to do |format|
      format.json { render json: { error: "Not found" }, status: :not_found }
      format.html do
        flash[:error] = "멤버를 찾을 수 없습니다."
        redirect_to organization_members_path(@organization.slug), status: :see_other
      end
    end
  end

  # An admin being downgraded to a non-admin role counts as demotion.
  # If they are the only admin in the org, block it — the org would be
  # left without a manager.
  def demoting_last_admin?(membership, new_role)
    return false unless membership.role == "admin"
    return false if new_role.to_s == "admin"
    last_admin?(membership)
  end

  def removing_last_admin?(membership)
    return false unless membership.role == "admin"
    last_admin?(membership)
  end

  def last_admin?(membership)
    @organization.org_memberships.where(role: "admin").where.not(id: membership.id).none?
  end
end
