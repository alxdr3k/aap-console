module ProjectApiKeys
  class RevokeService
    def initialize(project_api_key:, current_user_sub:)
      @project_api_key = project_api_key
      @project = project_api_key.project
      @current_user_sub = current_user_sub
    end

    def call
      unless project_api_key.revoked?
        project_api_key.update!(revoked_at: Time.current)
        audit!("project_api_key.revoke")
      end

      Result.success(project_api_key)
    end

    private

    attr_reader :project_api_key, :project, :current_user_sub

    def audit!(action)
      AuditLog.create!(
        organization: project.organization,
        project: project,
        user_sub: current_user_sub || "system",
        action: action,
        resource_type: "ProjectApiKey",
        resource_id: project_api_key.id.to_s,
        details: {
          name: project_api_key.name,
          token_prefix: project_api_key.token_prefix
        }
      )
    end
  end
end
