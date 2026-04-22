module Provisioning
  module Steps
    class LangfuseProjectCreate < BaseStep
      def execute
        org = project.organization
        raise "Organization has no Langfuse org ID" unless org.langfuse_org_id

        langfuse = LangfuseClient.new

        langfuse_project = langfuse.create_project(
          name: "#{org.slug}-#{project.slug}",
          org_id: org.langfuse_org_id
        )

        api_key = langfuse.create_api_key(project_id: langfuse_project["id"])

        # Store only public_key in snapshot; secret_key must NOT be persisted
        snapshot = {
          langfuse_project_id: langfuse_project["id"],
          langfuse_project_name: langfuse_project["name"],
          public_key: api_key.public_key
        }

        # Forward secrets to Config Server immediately; do not store in DB
        forward_secrets_to_config_server(api_key)

        snapshot
      end

      def rollback
        project_id = step_record.result_snapshot&.dig("langfuse_project_id")
        return unless project_id

        langfuse = LangfuseClient.new
        langfuse.delete_project(id: project_id)
      rescue BaseClient::ApiError => e
        raise unless e.is_a?(BaseClient::NotFoundError)
      end

      def already_completed?
        step_record.result_snapshot&.dig("langfuse_project_id").present?
      end

      private

      def forward_secrets_to_config_server(api_key)
        # Secrets are forwarded in config_server_apply step which has access to both
        # Langfuse keys and LiteLLM config. Store public_key only in snapshot for
        # reference; secret_key is passed via params to config_server_apply.
        # The orchestrator passes the result_snapshot forward via params.
        @step_record.provisioning_job.update_column(
          :warnings,
          (@step_record.provisioning_job.warnings || []).tap do |w|
            w << { note: "langfuse_keys_ready" }
          end
        )
        # Secret key is intentionally not stored anywhere.
        # ConfigServerApply reads it from params passed through orchestrator.
      end
    end
  end
end
