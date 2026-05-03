module Provisioning
  module Steps
    class KeycloakClientCreate < BaseStep
      def execute
        auth_config = project.project_auth_config
        raise "No auth_config found for project #{project.id}" unless auth_config

        client_id = auth_config.keycloak_client_id
        auth_type = auth_config.auth_type
        keycloak = KeycloakClient.new

        client_uuid = create_keycloak_client(keycloak, auth_type, client_id)

        # Phase 1: persist the external side-effect snapshot BEFORE writing
        # to project_auth_config. If the local DB write or the surrounding
        # step.update! raises, RollbackRunner can still find the Keycloak UUID
        # and delete the orphaned client.
        snapshot = { keycloak_client_uuid: client_uuid, keycloak_client_id: client_id }
        record_external_side_effect(snapshot)

        # Phase 2: mirror the UUID onto the auth_config row for read paths.
        # Skipped for PAK because no Keycloak client was created (uuid is nil).
        auth_config.update!(keycloak_client_uuid: client_uuid) if client_uuid
        cache_client_secret!(keycloak, client_uuid, auth_type) if client_uuid

        snapshot
      end

      def rollback
        uuid = step_record.result_snapshot&.dig("keycloak_client_uuid")
        return unless uuid

        keycloak = KeycloakClient.new
        keycloak.delete_client(uuid: uuid)
      rescue BaseClient::NotFoundError
        # Already deleted, nothing to do
      end

      def already_completed?
        uuid = step_record.result_snapshot&.dig("keycloak_client_uuid")
        return false unless uuid

        auth_config = project.project_auth_config
        return false unless auth_config&.keycloak_client_id

        # Look up the client by UUID directly. The list endpoint
        # `get_client_by_client_id` is a clientId search that only returns the
        # first match and depends on Keycloak's ordering — we already have the
        # UUID from the snapshot, so use the stable path-based GET. A
        # NotFoundError or ApiError surface as the step needing to re-run.
        client = KeycloakClient.new.get_client(uuid: uuid)

        # Treat any successful 200 against the UUID-targeted GET as
        # authoritative completion. Returning false on representation drift
        # (missing `id`, malformed body, omitted clientId) would push the
        # orchestrator back into `execute`, which unconditionally POSTs a new
        # client and either mints a duplicate or hard-fails on 409. Track
        # whether the live identity matches our snapshot — `after_skip` uses
        # this to decide if the secret cache refresh is safe.
        @client_identity_diverged = client_identity_diverged?(client, uuid, auth_config.keycloak_client_id)
        if @client_identity_diverged
          Rails.logger.warn(
            "[Provisioning::Steps::KeycloakClientCreate] live client identity " \
            "diverges from snapshot (uuid=#{uuid}, " \
            "live_id=#{client.is_a?(Hash) ? client["id"].inspect : 'n/a'}, " \
            "live_clientId=#{client.is_a?(Hash) ? client["clientId"].inspect : 'n/a'}, " \
            "expected_clientId=#{auth_config.keycloak_client_id.inspect}); treating step " \
            "as complete but skipping secret cache refresh"
          )
          record_identity_diverged_audit!(client, uuid, auth_config.keycloak_client_id)
        end
        true
      rescue BaseClient::NotFoundError
        # UUID from snapshot is gone. Fall back to client_id lookup to avoid
        # driving execute into an unconditional POST that hard-fails on 409
        # when the client was manually recreated under the same client_id.
        auth_config = project.project_auth_config
        return false unless auth_config&.keycloak_client_id

        begin
          client = KeycloakClient.new.get_client_by_client_id(auth_config.keycloak_client_id)
          live_id        = client.is_a?(Hash) ? client["id"].presence : nil
          live_client_id = client.is_a?(Hash) ? client["clientId"] : nil

          # Require exact clientId match and a present id before repairing local
          # state. The list endpoint is ordering-dependent; a fuzzy/partial first
          # result must not bind the project to the wrong Keycloak client.
          unless live_id.present? && live_client_id == auth_config.keycloak_client_id
            Rails.logger.warn(
              "[Provisioning::Steps::KeycloakClientCreate] snapshot UUID missing and " \
              "clientId fallback returned mismatched or empty result; treating as not found"
            )
            return false
          end

          # The client exists with the correct clientId under a new UUID (manual
          # recreation). Treat as completed and store the live UUID so after_skip
          # can repair the local mirror without triggering rollback.
          @live_uuid_from_fallback = live_id
          Rails.logger.info(
            "[Provisioning::Steps::KeycloakClientCreate] snapshot UUID missing but " \
            "client_id=#{auth_config.keycloak_client_id.inspect} found in Keycloak " \
            "(live_uuid=#{live_id.inspect}); will repair local UUID mirror"
          )
          true
        rescue BaseClient::NotFoundError, BaseClient::ApiError
          false
        end
      rescue BaseClient::ApiError
        false
      end

      def after_skip
        auth_config = project.project_auth_config
        return unless auth_config

        snapshot_uuid = step_record.result_snapshot&.dig("keycloak_client_uuid")

        # Repair the local UUID mirror from:
        # (a) a crash between external creation and local auth_config.update!, or
        # (b) a clientId fallback that found the client under a new UUID.
        # Without repair, auth UI, secret regeneration, and the delete step remain
        # gated on a stale or missing UUID.
        repair_uuid = @live_uuid_from_fallback.presence || (snapshot_uuid if !@client_identity_diverged)
        if repair_uuid.present? && auth_config.keycloak_client_uuid != repair_uuid
          auth_config.update!(keycloak_client_uuid: repair_uuid)
        end

        return unless auth_config.auth_type == "oidc"

        # Identity diverged from the snapshot — refreshing the secret cache
        # would expose a different client's secret. Drop any stale entry and
        # let the operator surface the divergence via the warning log.
        if @client_identity_diverged
          Provisioning::SecretCache.delete(step_record.provisioning_job_id)
          return
        end

        # Prefer the live UUID resolved by the clientId fallback; fall back to
        # the snapshot UUID or the already-repaired local mirror.
        client_uuid = @live_uuid_from_fallback.presence ||
                      snapshot_uuid ||
                      auth_config.keycloak_client_uuid
        return if client_uuid.blank?

        cache_client_secret!(KeycloakClient.new, client_uuid, auth_config.auth_type)
      end

      private

      def create_keycloak_client(keycloak, auth_type, client_id)
        redirect_uris = params[:redirect_uris] || []
        case auth_type
        when "oidc"
          response = keycloak.create_oidc_client(
            client_id: client_id,
            redirect_uris: redirect_uris
          )
        when "saml"
          response = keycloak.create_saml_client(
            client_id: client_id,
            attributes: params[:saml_attributes] || {}
          )
        when "oauth"
          response = keycloak.create_oauth_client(
            client_id: client_id,
            redirect_uris: redirect_uris
          )
        when "pak"
          return nil
        else
          raise "Unknown auth_type: #{auth_type}"
        end

        extract_uuid_from_response(response)
      end

      def extract_uuid_from_response(response)
        if response.is_a?(Hash)
          response["id"]
        else
          # Extract UUID from Location header (Keycloak 201 response)
          nil
        end
      end

      def record_identity_diverged_audit!(client, expected_uuid, expected_client_id)
        AuditLog.create!(
          organization: project.organization,
          project: project,
          # System-detected divergence has no acting user; mark the actor
          # explicitly so audit queries can distinguish it from operator
          # actions.
          user_sub: "system:keycloak-client-create",
          action: "auth_config.keycloak_client_diverged",
          resource_type: "ProjectAuthConfig",
          resource_id: project.project_auth_config&.id&.to_s,
          details: {
            expected_uuid: expected_uuid,
            expected_client_id: expected_client_id,
            live_id: client.is_a?(Hash) ? client["id"] : nil,
            live_client_id: client.is_a?(Hash) ? client["clientId"] : nil,
            provisioning_job_id: step_record.provisioning_job_id,
            provisioning_step_id: step_record.id
          }
        )
      rescue StandardError => e
        # Don't fail the step on an audit insert failure; the warn log above
        # already captures the divergence.
        Rails.logger.error(
          "[Provisioning::Steps::KeycloakClientCreate] failed to record identity " \
          "divergence audit for project #{project.id}: #{e.class}: #{e.message}"
        )
      end

      def client_identity_diverged?(client, expected_uuid, expected_client_id)
        return false unless client.is_a?(Hash)

        live_id = client["id"]
        live_client_id = client["clientId"]
        return true if live_id.present? && live_id != expected_uuid
        return true if expected_client_id.present? && live_client_id.present? && live_client_id != expected_client_id

        false
      end

      def cache_client_secret!(keycloak, client_uuid, auth_type)
        return unless auth_type == "oidc"

        Provisioning::SecretCache.delete(step_record.provisioning_job_id)
        Provisioning::SecretCache.write(
          step_record.provisioning_job,
          key: "client_secret",
          label: "Client Secret",
          value: keycloak.get_client_secret(uuid: client_uuid)
        )
      rescue StandardError => e
        Rails.logger.warn(
          "[Provisioning::Steps::KeycloakClientCreate] skipped secret cache " \
          "job=#{step_record.provisioning_job_id} step=#{step_record.id} " \
          "client_uuid=#{client_uuid} error=#{e.class}: #{e.message}"
        )
      end
    end
  end
end
