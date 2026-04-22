module Provisioning
  module Steps
    class KeycloakClientUpdate < BaseStep
      def execute
        auth_config = project.project_auth_config
        return { skipped: true, reason: "no_auth_config" } unless auth_config
        return { skipped: true, reason: "pak_auth" } if auth_config.auth_type == "pak"

        uuid = auth_config.keycloak_client_uuid
        return { skipped: true, reason: "no_uuid" } unless uuid

        keycloak = KeycloakClient.new

        # Fetch current state before mutating so rollback can restore it
        previous_state = keycloak.get_client_by_client_id(auth_config.keycloak_client_id)
        update_payload = build_update_payload

        keycloak.update_client(uuid: uuid, attributes: update_payload)

        {
          updated: true,
          keycloak_client_uuid: uuid,
          previous_state: previous_state
        }
      end

      def rollback
        snapshot = step_record.result_snapshot
        return unless snapshot&.dig("updated")

        uuid = snapshot["keycloak_client_uuid"]
        previous = snapshot["previous_state"]
        return unless uuid && previous

        keycloak = KeycloakClient.new
        keycloak.update_client(uuid: uuid, attributes: previous)
      rescue BaseClient::ApiError => e
        raise unless e.is_a?(BaseClient::NotFoundError)
      end

      def already_completed?
        step_record.result_snapshot&.dig("updated") == true ||
          step_record.result_snapshot&.dig("skipped") == true
      end

      private

      def build_update_payload
        payload = {}
        payload[:redirectUris] = params[:redirect_uris] if params[:redirect_uris]
        if params[:post_logout_redirect_uris]
          payload[:attributes] = {
            "post.logout.redirect.uris" => params[:post_logout_redirect_uris].join("##")
          }
        end
        payload
      end
    end
  end
end
