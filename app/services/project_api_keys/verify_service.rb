module ProjectApiKeys
  class VerifyService
    VERIFIABLE_PROJECT_STATUSES = %w[active update_pending].freeze

    def initialize(token:)
      @token = token
    end

    def call
      return Result.failure("Token is required") if token.blank?

      digest = ProjectApiKey.digest_token(token)
      verified_at = Time.current
      updated = ProjectApiKey
                .active
                .joins(:project)
                .where(token_digest: digest)
                .where(projects: { status: Project.statuses.values_at(*VERIFIABLE_PROJECT_STATUSES) })
                .update_all(last_used_at: verified_at, updated_at: verified_at)
      return Result.failure("Invalid token") unless updated == 1

      project_api_key = ProjectApiKey
                        .includes(project: :organization)
                        .find_by(token_digest: digest)
      return Result.failure("Invalid token") if project_api_key.nil?

      Result.success(project_api_key)
    end

    private

    attr_reader :token
  end
end
