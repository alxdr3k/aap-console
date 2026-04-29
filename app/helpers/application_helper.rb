module ApplicationHelper
  def navigation_organizations
    @navigation_organizations ||= current_authorization.organizations.order(:name)
  end

  def current_user_label
    Current.user_sub.presence || "unknown user"
  end

  def organization_role_label(organization)
    return "super admin" if current_authorization.super_admin?

    current_authorization.org_membership(organization)&.role || "read"
  end

  def organization_project_count(organization)
    current_authorization.accessible_projects(organization).count
  end

  def member_user_email(membership, user)
    user&.fetch("email", nil).presence || membership.user_sub
  end

  def member_user_name(user)
    [ user&.fetch("firstName", nil), user&.fetch("lastName", nil) ].compact_blank.join(" ").presence || "이름 없음"
  end

  def member_pending?(membership)
    membership.joined_at.blank?
  end

  def project_permission_for(membership, project)
    membership.project_permissions.detect { |permission| permission.project_id == project.id }
  end

  def flash_class(level)
    case level.to_sym
    when :notice, :success
      "flash flash--success"
    when :alert, :error
      "flash flash--error"
    else
      "flash flash--warning"
    end
  end
end
