module Provisioning
  module Steps
    # Crash-safe semantics for the Langfuse project + API key creation.
    #
    # Secret Zero-Store (PRD 6.1) forbids persisting the Langfuse secret key,
    # so on a worker crash between this step and ConfigServerApply we cannot
    # simply re-hand the same secret. Instead we re-mint: the Langfuse project
    # is preserved (creating it again would duplicate the resource), but the
    # API key is regenerated and the old one revoked. The fresh secret is
    # returned via :_ephemeral so ConfigServerApply receives a valid value
    # even after a resume.
    class LangfuseProjectCreate < BaseStep
      def execute
        org = project.organization
        raise "Organization has no Langfuse org ID" unless org.langfuse_org_id

        snap = step_record.result_snapshot
        return remint_api_key(snap) if resumable?(snap)

        initial_create(org)
      end

      def rollback
        project_id = step_record.result_snapshot&.dig("langfuse_project_id")
        return unless project_id

        langfuse = LangfuseClient.new

        # Revoke any leftover API keys we minted before deleting the project,
        # in case Langfuse holds references that block project deletion.
        revoke_recorded_api_key(langfuse)

        langfuse.delete_project(id: project_id)
      rescue BaseClient::ApiError => e
        raise unless e.is_a?(BaseClient::NotFoundError)
      end

      # Returns true only when the downstream config_server_apply step has
      # already consumed the secret (proven by its `local_persisted` flag).
      # Until then, every resume must re-mint the API key — the in-flight
      # secret was never persisted and is therefore unrecoverable.
      def already_completed?
        snap = step_record.result_snapshot
        return false unless snap&.dig("langfuse_project_id").present?

        downstream = step_record.provisioning_job
                                .provisioning_steps
                                .find_by(name: "config_server_apply")
        return false unless downstream

        downstream_snap = downstream.result_snapshot
        return false unless downstream_snap.is_a?(Hash)
        downstream_snap["local_persisted"] == true
      end

      private

      def resumable?(snap)
        snap.is_a?(Hash) && snap["langfuse_project_id"].present?
      end

      def initial_create(org)
        langfuse = LangfuseClient.new

        langfuse_project = langfuse.create_project(
          name: "#{org.slug}-#{project.slug}",
          org_id: org.langfuse_org_id
        )

        # Phase 1: record the Langfuse project side-effect before minting the
        # API key. Even if minting fails, RollbackRunner can find the project
        # and clean it up.
        project_snapshot = {
          langfuse_project_id: langfuse_project["id"],
          langfuse_project_name: langfuse_project["name"],
          project_created: true
        }
        record_external_side_effect(project_snapshot)

        api_key = langfuse.create_api_key(project_id: langfuse_project["id"])

        full_snapshot = project_snapshot.merge(
          public_key: api_key.public_key,
          last_api_key_id: api_key.id
        )
        record_external_side_effect(full_snapshot)

        full_snapshot.merge(_ephemeral: { langfuse_secret_key: api_key.secret_key })
      end

      def remint_api_key(snap)
        langfuse = LangfuseClient.new
        project_id = snap["langfuse_project_id"]

        # Revoke any prior key we recorded so secrets don't accumulate in
        # Langfuse for the same Console project.
        if (old_id = snap["last_api_key_id"])
          begin
            langfuse.delete_api_key(id: old_id)
          rescue BaseClient::ApiError
            # Tolerate already-revoked or missing key.
          end
        end

        api_key = langfuse.create_api_key(project_id: project_id)

        new_snapshot = snap.merge(
          "public_key" => api_key.public_key,
          "last_api_key_id" => api_key.id
        )
        record_external_side_effect(new_snapshot)

        new_snapshot.merge(_ephemeral: { langfuse_secret_key: api_key.secret_key })
      end

      def revoke_recorded_api_key(langfuse)
        api_key_id = step_record.result_snapshot&.dig("last_api_key_id")
        return unless api_key_id

        langfuse.delete_api_key(id: api_key_id)
      rescue BaseClient::ApiError
        # Tolerate already-deleted or missing key — project delete will follow.
      end
    end
  end
end
