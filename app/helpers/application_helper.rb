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
