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

      begin
        SecretRevealCache.delete(@project)
        SecretRevealCache.write(@project, key: "client_secret", label: "Client Secret", value: secret)
      rescue StandardError => e
        Rails.logger.error("Auth config secret cache write failed for project #{@project.id}: #{e.class}: #{e.message}")
        return Result.failure("Client Secret은 재발급되었지만 표시 캐시에 저장하지 못했습니다. 다시 재발급하세요.")
      end

      AuditLog.create!(
        organization: @project.organization,
        project: @project,
        user_sub: @current_user_sub,
        action: "auth_config.secret_regenerated",
        resource_type: "ProjectAuthConfig",
        resource_id: auth_config.id.to_s,
        details: { auth_type: auth_config.auth_type, keycloak_client_uuid: auth_config.keycloak_client_uuid }
      )

      Result.success(secret_revealed: true)
    rescue BaseClient::ApiError => e
      Result.failure("Client Secret 재발급에 실패했습니다: #{e.message}")
    end

    private

    def active_job_exists?
      @project.provisioning_jobs.where(status: ProvisioningJob::ACTIVE_STATUSES).exists?
    end
  end
end
