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
        auth_config.update!(keycloak_client_uuid: client_uuid)

        { keycloak_client_uuid: client_uuid, keycloak_client_id: client_id }
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

        keycloak = KeycloakClient.new
        auth_config = project.project_auth_config
        return false unless auth_config&.keycloak_client_id

        clients = keycloak.get_client_by_client_id(client_id: auth_config.keycloak_client_id)
        clients.any?
      rescue BaseClient::ApiError
        false
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
    end
  end
end
