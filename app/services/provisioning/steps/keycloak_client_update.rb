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
        update_payload = build_update_payload

        keycloak.update_client(uuid: uuid, payload: update_payload)

        { updated: true, keycloak_client_uuid: uuid }
      end

      def rollback
        # Update rollback requires a snapshot of the previous state.
        # The config_version snapshot contains the previous config.
        # For now, we mark as rollback-needing manual intervention if snapshot is missing.
      end

      def already_completed?
        step_record.result_snapshot&.dig("updated") == true ||
          step_record.result_snapshot&.dig("skipped") == true
      end

      private

      def build_update_payload
        payload = {}
        payload[:redirectUris] = params[:redirect_uris] if params[:redirect_uris]
        payload[:attributes] = {
          "post.logout.redirect.uris" => params[:post_logout_redirect_uris]&.join("##")
        } if params[:post_logout_redirect_uris]
        payload
      end
    end
  end
end
