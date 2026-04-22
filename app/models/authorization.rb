class Authorization
  ROLE_HIERARCHY = { read: 1, write: 2, admin: 3 }.freeze

  def initialize(user_sub:, realm_roles: [])
    @user_sub = user_sub
    @realm_roles = Array(realm_roles)
    @membership_cache = {}
  end

  def super_admin?
    @realm_roles.include?("super_admin")
  end

  def org_membership(organization)
    @membership_cache[organization.id] ||=
      OrgMembership.find_by(organization: organization, user_sub: @user_sub)
  end

  def organizations
    Organization.joins(:org_memberships).where(org_memberships: { user_sub: @user_sub })
  end

  def project_role(project)
    return :admin if super_admin?

    membership = org_membership(project.organization)
    return nil unless membership

    return :admin if membership.admin?

    perm = ProjectPermission.find_by(org_membership: membership, project: project)
    perm&.role&.to_sym
  end

  def accessible_projects(organization)
    membership = org_membership(organization)
    return Project.none unless membership

    if membership.admin?
      organization.projects.where.not(status: :deleted)
    else
      Project.joins(:project_permissions)
             .where(project_permissions: { org_membership: membership })
             .where.not(status: :deleted)
    end
  end

  def can?(action, resource)
    case action
    when :manage_org
      super_admin? || org_membership(resource)&.admin?
    when :read_project
      role = project_role(resource)
      role.present?
    when :write_project
      role = project_role(resource)
      role.present? && ROLE_HIERARCHY[role] >= ROLE_HIERARCHY[:write]
    end
  end
end
