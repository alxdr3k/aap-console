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
    when "active"             then "badge badge--active"
    when "provisioning"       then "badge badge--provisioning"
    when "update_pending"     then "badge badge--in-progress"
    when "deleting"           then "badge badge--rolling-back"
    when "provision_failed"   then "badge badge--prov-failed"
    when "deleted"            then "badge badge--muted"
    else                           "badge badge--muted"
    end
  end

  def project_status_label(project)
    case project.status
    when "active"             then "활성"
    when "provisioning"       then "생성중"
    when "update_pending"     then "업데이트 대기"
    when "deleting"           then "삭제중"
    when "provision_failed"   then "생성 실패"
    when "deleted"            then "삭제됨"
    else project.status
    end
  end

  def provisioning_status_badge_class(job)
    return "badge badge--muted" unless job

    case job.status
    when "completed"               then "badge badge--completed"
    when "completed_with_warnings" then "badge badge--warnings"
    when "failed"                  then "badge badge--failed"
    when "rollback_failed"         then "badge badge--rollback-fail"
    when "rolled_back"             then "badge badge--rolled-back"
    when "in_progress"             then "badge badge--in-progress"
    when "retrying"                then "badge badge--retrying"
    when "rolling_back"            then "badge badge--rolling-back"
    when "pending"                 then "badge badge--pending"
    else                                "badge badge--muted"
    end
  end

  def provisioning_status_label(job)
    return "-" unless job

    case job.status
    when "completed"               then "완료"
    when "completed_with_warnings" then "완료 (경고)"
    when "failed"                  then "실패"
    when "rollback_failed"         then "실패 (수동 조치 필요)"
    when "rolled_back"             then "실패 (정리 완료)"
    when "in_progress"             then "진행중"
    when "retrying"                then "재시도중"
    when "rolling_back"            then "정리중"
    when "pending"                 then "대기"
    else job.status
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

  def project_list_value(values, fallback: "아직 없음")
    entries = Array(values).compact_blank
    return fallback if entries.blank?

    entries.join(", ")
  end

  def config_version_change_badge_class(config_version)
    case config_version.change_type
    when "create"
      "badge"
    when "update"
      "badge badge--warning"
    when "delete"
      "badge badge--danger"
    when "rollback"
      "badge badge--muted"
    else
      "badge badge--muted"
    end
  end

  def config_diff_line_class(line)
    case line.kind
    when :meta
      "diff-view__line diff-view__line--meta"
    when :added
      "diff-view__line diff-view__line--added"
    when :removed
      "diff-view__line diff-view__line--removed"
    else
      "diff-view__line"
    end
  end

  def config_diagnostic_badge_class(status)
    case status.to_s
    when "restored"
      "badge"
    when "failed"
      "badge badge--danger"
    when "not_applicable_no_snapshot", "not_started"
      "badge badge--muted"
    else
      "badge badge--warning"
    end
  end

  def config_diagnostic_label(status)
    case status.to_s
    when "restored"
      "restored"
    when "failed"
      "failed"
    when "not_applicable_no_snapshot"
      "snapshot 없음"
    when "not_started"
      "시작 안 됨"
    else
      status.to_s
    end
  end

  def rollback_result_badge_class(status)
    case status.to_s
    when "completed"
      "badge"
    when "blocked"
      "badge badge--warning"
    else
      "badge badge--danger"
    end
  end

  def short_datetime(value)
    value&.strftime("%Y-%m-%d %H:%M") || "-"
  end

  def provisioning_duration(job)
    return "-" unless job&.started_at
    return "진행 중" unless job.completed_at

    distance_of_time_in_words(job.started_at, job.completed_at)
  end

  def provisioning_operation_title(job)
    case job.operation
    when "create"
      "Project 생성 프로비저닝"
    when "update"
      "설정 변경 프로비저닝"
    when "delete"
      "Project 삭제 프로비저닝"
    else
      "프로비저닝"
    end
  end

  def provisioning_step_label(step)
    step.name.tr("_", " ").titleize
  end

  def provisioning_step_status_badge_class(step)
    case step.status
    when "completed"               then "badge badge--completed"
    when "skipped"                 then "badge badge--muted"
    when "in_progress"             then "badge badge--in-progress"
    when "failed"                  then "badge badge--failed"
    when "rollback_failed"         then "badge badge--rollback-fail"
    when "rolled_back"             then "badge badge--rolled-back"
    when "retrying"                then "badge badge--retrying"
    when "rolling_back"            then "badge badge--rolling-back"
    when "pending"                 then "badge badge--pending"
    else                                "badge badge--muted"
    end
  end

  def provisioning_step_status_label(step)
    case step.status
    when "completed"      then "완료"
    when "skipped"        then "건너뜀"
    when "in_progress"    then "진행중..."
    when "failed"         then "실패"
    when "rollback_failed" then "롤백 실패"
    when "rolled_back"    then "롤백 완료"
    when "retrying"       then "재시도중"
    when "rolling_back"   then "정리중"
    when "pending"        then "대기"
    else step.status
    end
  end

  def provisioning_target_path(job)
    if job.operation == "delete" || job.project.deleted?
      organization_path(job.project.organization.slug)
    else
      organization_project_path(job.project.organization.slug, job.project.slug)
    end
  end

  def provisioning_target_label(job)
    job.operation == "delete" || job.project.deleted? ? "Organization으로 이동" : "Project 상세로 이동"
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
