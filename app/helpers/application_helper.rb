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

  def project_status_badge_class(project)
    case project.status
    when "active"
      "badge"
    when "provisioning", "update_pending", "deleting"
      "badge badge--warning"
    when "deleted", "provision_failed"
      "badge badge--danger"
    else
      "badge badge--muted"
    end
  end

  def provisioning_status_badge_class(job)
    return "badge badge--muted" unless job

    case job.status
    when "completed", "completed_with_warnings"
      "badge"
    when "failed", "rollback_failed"
      "badge badge--danger"
    when "rolled_back"
      "badge badge--muted"
    else
      "badge badge--warning"
    end
  end

  def project_snapshot_list(snapshot, key)
    value = snapshot&.fetch(key.to_s, nil) || snapshot&.fetch(key.to_sym, nil)
    Array(value).compact_blank
  end

  def project_snapshot_value(snapshot, key, fallback: "아직 없음")
    value = snapshot&.fetch(key.to_s, nil) || snapshot&.fetch(key.to_sym, nil)
    return fallback if value.blank?
    return value.join(", ") if value.is_a?(Array)

    value.to_s
  end

  def short_datetime(value)
    value&.strftime("%Y-%m-%d %H:%M") || "-"
  end

  def provisioning_duration(job)
    return "-" unless job&.started_at
    return "진행 중" unless job.completed_at

    distance_of_time_in_words(job.started_at, job.completed_at)
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
