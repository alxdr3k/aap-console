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

      cache_failed = false
      begin
        SecretRevealCache.delete(@project)
        SecretRevealCache.write(@project, key: "client_secret", label: "Client Secret", value: secret)
      rescue StandardError => e
        # The upstream secret has already been rotated and the previous secret is
        # gone forever. Capture the fresh value in the result so the caller can
        # render it once in this same response cycle — never persist the value
        # outside the cache TTL or this in-memory result.
        Rails.logger.error("Auth config secret cache write failed for project #{@project.id}: #{e.class}: #{e.message}")
        cache_failed = true
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
          keycloak_client_uuid: auth_config.keycloak_client_uuid,
          cache_failed: cache_failed
        }
      )

      Result.success(
        secret_revealed: true,
        cache_failed: cache_failed,
        reveal_payload: cache_failed ? in_memory_reveal_payload(secret) : SecretRevealCache.read(@project)
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
        # Signal to JSON callers that the persistent reveal cache could not
        # store this payload; the secret only exists in this single response.
        "cache_failed" => true,
        "expires_at" => now
      }
    end
  end
end
