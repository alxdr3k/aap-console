module Provisioning
  module Steps
    class KeycloakClientDelete < BaseStep
      def execute
        auth_config = project.project_auth_config
        return { deleted: true, reason: "no_auth_config" } unless auth_config
        return { deleted: true, reason: "no_keycloak_client" } if auth_config.auth_type == "pak"

        client_id = auth_config.keycloak_client_id
        unless client_id&.start_with?("aap-")
          raise "Refusing to delete non-aap- Keycloak client: #{client_id.inspect}"
        end

        uuid = auth_config.keycloak_client_uuid
        return { deleted: true, reason: "no_uuid" } unless uuid

        keycloak = KeycloakClient.new
        keycloak.delete_client(uuid: uuid, expected_client_id: client_id)

        { deleted: true, keycloak_client_uuid: uuid }
      rescue BaseClient::NotFoundError
        { deleted: true, reason: "already_deleted" }
      rescue KeycloakClient::IdentityMismatchError => e
        # Stale UUID resolves to a different aap-prefixed client. Deleting
        # the foreign client would be a cross-project breach, but reporting
        # success would mark this project deleted while its real Keycloak
        # client remains active. Audit and propagate so the orchestrator
        # records a failure that an operator must reconcile.
        AuditLog.create!(
          organization: project.organization,
          project: project,
          user_sub: "system:keycloak-client-delete",
          action: "auth_config.keycloak_client_diverged",
          resource_type: "ProjectAuthConfig",
          resource_id: project.project_auth_config&.id&.to_s,
          details: {
            expected_uuid: uuid,
            expected_client_id: client_id,
            live_client_id: e.live_client_id,
            detection_phase: "client_delete",
            provisioning_job_id: step_record.provisioning_job_id,
            provisioning_step_id: step_record.id
          }
        )
        raise
      end

      def rollback
        # Deletion is irreversible at this level; rollback is a no-op.
        # The orchestrator's all-or-nothing semantics means we shouldn't
        # reach here in normal flows (delete steps don't roll back).
      end

      def already_completed?
        auth_config = project.project_auth_config
        return true unless auth_config&.keycloak_client_uuid

        keycloak = KeycloakClient.new
        keycloak.get_client_by_client_id(auth_config.keycloak_client_id)
        false
      rescue BaseClient::NotFoundError
        true
      rescue BaseClient::ApiError
        false
      end
    end
  end
end
