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
      return Result.failure("Keycloak client ID가 아직 설정되지 않았습니다.") if auth_config.keycloak_client_id.blank?
      return Result.failure("Another provisioning job is in progress") if active_job_exists?

      secret = KeycloakClient.new.regenerate_client_secret(
        uuid: auth_config.keycloak_client_uuid,
        expected_client_id: auth_config.keycloak_client_id
      )

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
    rescue KeycloakClient::RotationVerifyError => e
      Rails.logger.warn(
        "[AuthConfigs::RegenerateClientSecretService] post-rotation verify failed " \
        "for project=#{@project.id}: #{e.message}"
      )
      AuditLog.create!(
        organization: @project.organization,
        project: @project,
        user_sub: @current_user_sub,
        action: "auth_config.keycloak_client_diverged",
        resource_type: "ProjectAuthConfig",
        resource_id: auth_config.id.to_s,
        details: {
          detection_phase: "secret_regenerate",
          divergence_stage: "post_fetch",
          # POST committed a rotation, but verify could not confirm the
          # identity binding. The discarded secret may belong to the
          # expected client OR to a foreign client; operators must
          # reconcile against Keycloak directly.
          secret_rotated: true,
          post_verify_failed: true,
          expected_client_id: auth_config.keycloak_client_id,
          keycloak_client_uuid: auth_config.keycloak_client_uuid,
          cause_class: e.cause_class,
          cause_message: e.cause_message
        }
      )
      Result.failure(
        "Client Secret 회전이 시작되었지만 검증에 실패했습니다. " \
        "운영팀에 즉시 보고하세요 — Keycloak에 새 secret이 이미 적용되었을 수 있습니다."
      )
    rescue KeycloakClient::IdentityMismatchError => e
      Rails.logger.warn(
        "[AuthConfigs::RegenerateClientSecretService] aborted for project=#{@project.id} " \
        "stage=#{e.stage}: #{e.message}"
      )
      AuditLog.create!(
        organization: @project.organization,
        project: @project,
        user_sub: @current_user_sub,
        action: "auth_config.keycloak_client_diverged",
        resource_type: "ProjectAuthConfig",
        resource_id: auth_config.id.to_s,
        details: {
          detection_phase: "secret_regenerate",
          divergence_stage: e.stage,
          # post_fetch means the POST already rotated the foreign client's
          # secret in Keycloak. Operators must rotate the affected client a
          # second time to invalidate the value that briefly existed
          # in-process here.
          secret_rotated: e.stage == "post_fetch",
          expected_client_id: auth_config.keycloak_client_id,
          live_client_id: e.live_client_id,
          keycloak_client_uuid: auth_config.keycloak_client_uuid
        }
      )

      if e.stage == "post_fetch"
        # Best-effort: drop an audit row on every ProjectAuthConfig that
        # claims this keycloak_client_id (until a DB-backed uniqueness
        # invariant exists, find_by would arbitrarily pick the first match
        # and miss other affected projects).
        affected_configs = ProjectAuthConfig.where(keycloak_client_id: e.live_client_id).to_a
        if affected_configs.size > 1
          Rails.logger.warn(
            "[AuthConfigs::RegenerateClientSecretService] multiple ProjectAuthConfig rows " \
            "share keycloak_client_id=#{e.live_client_id.inspect}; auditing all #{affected_configs.size} rows"
          )
        end
        affected_configs.each do |affected|
          begin
            AuditLog.create!(
              organization: affected.project.organization,
              project: affected.project,
              user_sub: "system:keycloak-client-rotation-impact",
              action: "auth_config.keycloak_client_secret_unintentionally_rotated",
              resource_type: "ProjectAuthConfig",
              resource_id: affected.id.to_s,
              details: {
                triggering_project_id: @project.id,
                triggering_user_sub: @current_user_sub,
                live_client_id: e.live_client_id,
                shared_keycloak_client_uuid: auth_config.keycloak_client_uuid,
                action_required: "rotate_client_secret",
                affected_match_count: affected_configs.size
              }
            )
          rescue StandardError => audit_error
            Rails.logger.error(
              "[AuthConfigs::RegenerateClientSecretService] failed to record " \
              "affected-client audit for project=#{affected.project_id}: " \
              "#{audit_error.class}: #{audit_error.message}"
            )
          end
        end

        Result.failure(
          "Keycloak client identity mismatch — 다른 client의 secret이 이미 회전되었을 수 있습니다. " \
          "운영팀에 즉시 보고하고 영향받은 client를 다시 회전하세요."
        )
      else
        Result.failure("Keycloak client identity mismatch. 운영팀에 문의하세요.")
      end
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
