module ProjectApiKeys
  class IssueService
    TOKEN_PREFIX = "pak-"
    TOKEN_LENGTH = 40
    MAX_ATTEMPTS = 5

    def initialize(project:, name:, current_user_sub:)
      @project = project
      @name = name
      @current_user_sub = current_user_sub
    end

    def call
      attempts = 0

      begin
        attempts += 1
        token = generate_token
        project_api_key = project.project_api_keys.create!(
          name: name,
          token_digest: ProjectApiKey.digest_token(token),
          token_prefix: token.first(ProjectApiKey::TOKEN_PREFIX_LENGTH)
        )
      rescue ActiveRecord::RecordNotUnique
        retry if attempts < MAX_ATTEMPTS
        return Result.failure("Token collision; retry later")
      rescue ActiveRecord::RecordInvalid => e
        retry if token_digest_collision?(e.record) && attempts < MAX_ATTEMPTS

        return Result.failure(e.record.errors.full_messages.to_sentence)
      end

      audit!("project_api_key.create", project_api_key)
      Result.success(project_api_key: project_api_key, token: token)
    end

    private

    attr_reader :project, :name, :current_user_sub

    def generate_token
      "#{TOKEN_PREFIX}#{SecureRandom.alphanumeric(TOKEN_LENGTH)}"
    end

    def token_digest_collision?(record)
      record.errors.added?(:token_digest, :taken)
    end

    def audit!(action, project_api_key)
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
