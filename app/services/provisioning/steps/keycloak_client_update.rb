module Provisioning
  module Steps
    class KeycloakClientUpdate < BaseStep
      def execute
        auth_config = project.project_auth_config
        return { skipped: true, reason: "no_auth_config" } unless auth_config
        return { skipped: true, reason: "pak_auth" } if auth_config.auth_type == "pak"
        return { skipped: true, reason: "no_auth_params" } unless auth_config_params_present?

        uuid = auth_config.keycloak_client_uuid
        return { skipped: true, reason: "no_uuid" } unless uuid

        keycloak = KeycloakClient.new

        previous_state = keycloak.get_client_by_client_id(auth_config.keycloak_client_id)
        previous_redirect_uris = auth_config.redirect_uris&.dup
        previous_post_logout_redirect_uris = auth_config.post_logout_redirect_uris&.dup

        keycloak.update_client(uuid: uuid, attributes: build_update_payload)

        db_updates = {}
        db_updates[:redirect_uris] = params[:redirect_uris] if params.key?(:redirect_uris)
        if params.key?(:post_logout_redirect_uris)
          db_updates[:post_logout_redirect_uris] = params[:post_logout_redirect_uris]
        end
        auth_config.update!(db_updates) if db_updates.any?

        {
          updated: true,
          keycloak_client_uuid: uuid,
          previous_state: previous_state,
          previous_redirect_uris: previous_redirect_uris,
          previous_post_logout_redirect_uris: previous_post_logout_redirect_uris
        }
      end

      def rollback
        snapshot = step_record.result_snapshot
        return unless snapshot&.dig("updated")

        uuid = snapshot["keycloak_client_uuid"]
        previous = snapshot["previous_state"]

        if uuid && previous
          keycloak = KeycloakClient.new
          keycloak.update_client(uuid: uuid, attributes: previous)
        end

        if (config = project.project_auth_config)
          restore = {}
          if snapshot.key?("previous_redirect_uris")
            restore[:redirect_uris] = snapshot["previous_redirect_uris"]
          end
          if snapshot.key?("previous_post_logout_redirect_uris")
            restore[:post_logout_redirect_uris] = snapshot["previous_post_logout_redirect_uris"]
          end
          config.update!(restore) if restore.any?
        end
      rescue BaseClient::ApiError => e
        raise unless e.is_a?(BaseClient::NotFoundError)
      end

      def already_completed?
        step_record.result_snapshot&.dig("updated") == true ||
          step_record.result_snapshot&.dig("skipped") == true
      end

      private

      def auth_config_params_present?
        params.key?(:redirect_uris) || params.key?(:post_logout_redirect_uris)
      end

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
