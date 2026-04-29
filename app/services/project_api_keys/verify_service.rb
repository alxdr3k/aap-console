module ProjectApiKeys
  class VerifyService
    VERIFIABLE_PROJECT_STATUSES = %w[active update_pending].freeze

    def initialize(token:)
      @token = token
    end

    def call
      return Result.failure("Token is required") if token.blank?

      project_api_key = ProjectApiKey
                        .active
                        .includes(project: :organization)
                        .joins(:project)
                        .where(projects: { status: Project.statuses.values_at(*VERIFIABLE_PROJECT_STATUSES) })
                        .find_by(token_digest: ProjectApiKey.digest_token(token))
      return Result.failure("Invalid token") unless project_api_key

      project_api_key.update_columns(last_used_at: Time.current)
      Result.success(project_api_key)
    end

    private

    attr_reader :token
  end
end
