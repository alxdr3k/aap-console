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

        existing = step_record.result_snapshot
        if resume_local_persistence?(existing)
          return resume_from_snapshot(existing, auth_config)
        end

        keycloak = KeycloakClient.new

        previous_state = keycloak.get_client_by_client_id(auth_config.keycloak_client_id)
        previous_redirect_uris = auth_config.redirect_uris&.dup
        previous_post_logout_redirect_uris = auth_config.post_logout_redirect_uris&.dup

        keycloak.update_client(uuid: uuid, attributes: build_update_payload,
                               expected_client_id: auth_config.keycloak_client_id)

        # Phase 1: persist rollback metadata + "external happened" marker
        # before any local DB write so that RollbackRunner can restore the
        # Keycloak client even if Phase 2 (auth_config.update!) raises.
        # `local_persisted: false` keeps already_completed? from mistakenly
        # skipping a half-applied step on resume.
        partial_snapshot = {
          updated: true,
          local_persisted: false,
          keycloak_client_uuid: uuid,
          previous_state: previous_state,
          previous_redirect_uris: previous_redirect_uris,
          previous_post_logout_redirect_uris: previous_post_logout_redirect_uris
        }
        record_external_side_effect(partial_snapshot)

        # Phase 2: local DB mirror.
        apply_local_db_updates!(auth_config)

        partial_snapshot.merge(local_persisted: true)
      end

      def rollback
        snapshot = step_record.result_snapshot
        return unless snapshot&.dig("updated")

        uuid = snapshot["keycloak_client_uuid"]
        previous = snapshot["previous_state"]

        if uuid && previous
          begin
            expected = project.project_auth_config&.keycloak_client_id
            KeycloakClient.new.update_client(uuid: uuid, attributes: previous,
                                             expected_client_id: expected) if expected
          rescue BaseClient::NotFoundError
            # Client already deleted — Keycloak rollback is implicitly done
          rescue KeycloakClient::IdentityMismatchError => e
            # Audit and re-raise so RollbackRunner does not silently mark the
            # step rolled_back while the foreign Keycloak client retains the
            # mutation we should have reverted. Operators must reconcile.
            AuditLog.create!(
              organization: project.organization,
              project: project,
              user_sub: "system:keycloak-client-update",
              action: "auth_config.keycloak_client_diverged",
              resource_type: "ProjectAuthConfig",
              resource_id: project.project_auth_config&.id&.to_s,
              details: {
                expected_uuid: uuid,
                expected_client_id: expected,
                live_client_id: e.live_client_id,
                detection_phase: "update_rollback",
                provisioning_job_id: step_record.provisioning_job_id,
                provisioning_step_id: step_record.id
              }
            )
            raise
          end
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
      end

      def already_completed?
        snap = step_record.result_snapshot
        return false unless snap
        return true if snap["skipped"] == true

        # Both halves must be true. "updated" alone means the Keycloak
        # mutation happened but the DB mirror (redirect_uris / post_logout)
        # is missing, which would let subsequent reads and merges diverge
        # from the real Keycloak client.
        snap["updated"] == true && snap["local_persisted"] == true
      end

      private

      def auth_config_params_present?
        params.key?(:redirect_uris) || params.key?(:post_logout_redirect_uris)
      end

      def resume_local_persistence?(snap)
        snap.is_a?(Hash) &&
          snap["updated"] == true &&
          snap["local_persisted"] != true
      end

      # Resumes Phase 2 from a snapshot that was already committed to disk
      # after Keycloak accepted the update. Does not re-call Keycloak: the
      # mutation already succeeded once. auth_config.update! is idempotent
      # for the same values, so repeated resume attempts are safe.
      def resume_from_snapshot(snap, auth_config)
        apply_local_db_updates!(auth_config)
        snap.merge("local_persisted" => true)
      end

      def apply_local_db_updates!(auth_config)
        db_updates = {}
        db_updates[:redirect_uris] = params[:redirect_uris] if params.key?(:redirect_uris)
        if params.key?(:post_logout_redirect_uris)
          db_updates[:post_logout_redirect_uris] = params[:post_logout_redirect_uris]
        end
        auth_config.update!(db_updates) if db_updates.any?
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
