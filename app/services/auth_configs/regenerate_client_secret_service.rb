module AuthConfigs
  class RegenerateClientSecretService
    def initialize(project:, current_user_sub:)
      @project = project
      @current_user_sub = current_user_sub
    end

    def call
      auth_config = @project.project_auth_config
      return Result.failure("인증 설정을 찾을 수 없습니다.") unless auth_config
      return Result.failure("OIDC Project에서만 Client Secret을 재발급할 수 있습니다.") unless auth_config.auth_type == "oidc"
      return Result.failure("Keycloak client가 아직 준비되지 않았습니다.") if auth_config.keycloak_client_uuid.blank?
      return Result.failure("Another provisioning job is in progress") if active_job_exists?

      secret = KeycloakClient.new.regenerate_client_secret(uuid: auth_config.keycloak_client_uuid)

      # All callers (browser HTML, Turbo, JSON) now render the secret from
      # in_memory_reveal_payload — no redirect through the shared cache exists.
      # Skip the write entirely so the rotated secret never enters the
      # per-project cache; only clear any stale entry from a previous rotation.
      begin
        SecretRevealCache.delete(@project)
      rescue StandardError => e
        Rails.logger.error("Auth config secret cache clear failed for project #{@project.id}: #{e.class}: #{e.message}")
      end

      AuditLog.create!(
        organization: @project.organization,
        project: @project,
        user_sub: @current_user_sub,
        action: "auth_config.secret_regenerated",
        resource_type: "ProjectAuthConfig",
        resource_id: auth_config.id.to_s,
        details: {
          auth_type: auth_config.auth_type,
          keycloak_client_uuid: auth_config.keycloak_client_uuid
        }
      )

      Result.success(
        secret_revealed: true,
        cache_failed: false,
        reveal_payload: in_memory_reveal_payload(secret)
      )
    rescue BaseClient::ApiError => e
      Result.failure("Client Secret 재발급에 실패했습니다: #{e.message}")
    end

    private

    def active_job_exists?
      @project.provisioning_jobs.where(status: ProvisioningJob::ACTIVE_STATUSES).exists?
    end

    def in_memory_reveal_payload(secret)
      now = Time.current.iso8601(6)
      {
        "organization_id" => @project.organization_id,
        "project_id" => @project.id,
        "secrets" => {
          "client_secret" => { "label" => "Client Secret", "value" => secret }
        },
        "generated_at" => now,
        "expires_at" => now
      }
    end
  end
end
