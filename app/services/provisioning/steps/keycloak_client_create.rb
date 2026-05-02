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
        # UUID from the snapshot, so use the stable path-based GET. A recreated
        # client with the same clientId but a different UUID will surface as
        # NotFoundError on this call and force the step to run again.
        client = KeycloakClient.new.get_client(uuid: uuid)
        return false unless client.is_a?(Hash) && client["id"] == uuid

        # Treat the UUID match as authoritative completion. A clientId mismatch
        # at this layer would mean an out-of-band Keycloak edit; we log the
        # divergence for the operator instead of forcing a duplicate POST that
        # would either succeed under a different clientId or fail with 409.
        if auth_config.keycloak_client_id.present? &&
           client["clientId"].present? &&
           client["clientId"] != auth_config.keycloak_client_id
          Rails.logger.warn(
            "[Provisioning::Steps::KeycloakClientCreate] live clientId " \
            "#{client["clientId"]} differs from snapshot " \
            "#{auth_config.keycloak_client_id} for uuid=#{uuid}; treating step as complete"
          )
        end
        true
      rescue BaseClient::NotFoundError
        false
      rescue BaseClient::ApiError
        false
      end

      def after_skip
        auth_config = project.project_auth_config
        return unless auth_config&.auth_type == "oidc"

        client_uuid = step_record.result_snapshot&.dig("keycloak_client_uuid") || auth_config.keycloak_client_uuid
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
