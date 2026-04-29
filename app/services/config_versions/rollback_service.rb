module ConfigVersions
  class RollbackService
    ResultData = Struct.new(:rollback_version, :diagnostics, keyword_init: true)

    def initialize(config_version:, current_user_sub:)
      @config_version = config_version
      @project = config_version.project
      @organization = @project.organization
      @current_user_sub = current_user_sub
      @attempt_id = SecureRandom.uuid
    end

    def call
      return conflict if active_job_exists?

      response = revert_config_server!
      rollback_version = record_rollback_version!(response["version"])
      diagnostics = success_diagnostics

      audit!("config.rollback.completed", diagnostics: diagnostics, rollback_version_id: rollback_version.version_id)

      Result.success(ResultData.new(rollback_version: rollback_version, diagnostics: diagnostics))
    rescue BaseClient::ApiError => e
      diagnostics = failure_diagnostics(e)
      audit!("config.rollback.failed", diagnostics: diagnostics, error: e.message)
      Result.failure(
        status: :bad_gateway,
        response_status: "failed",
        message: "Config Server rollback failed",
        diagnostics: diagnostics
      )
    end

    private

    attr_reader :config_version, :project, :organization, :current_user_sub, :attempt_id

    def active_job_exists?
      project.provisioning_jobs.where(status: ProvisioningJob::ACTIVE_STATUSES).exists?
    end

    def conflict
      diagnostics = { config_server: "not_started" }
      audit!("config.rollback.blocked", diagnostics: diagnostics, error: "Another provisioning job is in progress")
      Result.failure(
        status: :conflict,
        response_status: "blocked",
        message: "Another provisioning job is in progress",
        diagnostics: diagnostics
      )
    end

    def revert_config_server!
      ConfigServerClient.new.revert_changes(
        org: organization.slug,
        project: project.slug,
        service: "litellm",
        target_version: config_version.version_id,
        idempotency_key: "config-version-rollback-#{config_version.id}-#{attempt_id}"
      )
    end

    def record_rollback_version!(external_version_id)
      version_id = external_version_id.presence || config_version.version_id
      ConfigVersion.create!(
        project: project,
        version_id: version_id,
        change_type: "rollback",
        change_summary: "Rolled back to #{config_version.version_id}",
        changed_by_sub: current_user_sub,
        snapshot: config_version.snapshot
      )
    end

    def success_diagnostics
      {
        config_server: "restored",
        keycloak: "not_applicable_no_snapshot",
        langfuse: "not_applicable_no_snapshot"
      }
    end

    def failure_diagnostics(error)
      {
        config_server: "failed",
        keycloak: "not_started",
        langfuse: "not_started",
        error: error.message
      }
    end

    def audit!(action, details)
      AuditLog.create!(
        organization: organization,
        project: project,
        user_sub: current_user_sub,
        action: action,
        resource_type: "ConfigVersion",
        resource_id: config_version.id.to_s,
        details: {
          target_version_id: config_version.version_id,
          rollback_attempt_id: attempt_id
        }.merge(details)
      )
    end
  end
end
