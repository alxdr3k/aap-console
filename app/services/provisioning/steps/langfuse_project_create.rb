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

        # Store only public_key in snapshot; secret_key must NOT be persisted to DB.
        # secret_key is returned via :_ephemeral so the orchestrator passes it as
        # params[:langfuse_secret_key] to the downstream config_server_apply step.
        {
          langfuse_project_id: langfuse_project["id"],
          langfuse_project_name: langfuse_project["name"],
          public_key: api_key.public_key,
          _ephemeral: { langfuse_secret_key: api_key.secret_key }
        }
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
    end
  end
end
