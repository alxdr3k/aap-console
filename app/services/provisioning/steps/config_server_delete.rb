module Provisioning
  module Steps
    class ConfigServerDelete < BaseStep
      def execute
        client = ConfigServerClient.new
        org = project.organization

        client.delete_changes(
          org: org.slug,
          project: project.slug,
          service: "litellm",
          idempotency_key: "config-delete-#{step_record.id}"
        )

        { deleted: true }
      rescue BaseClient::NotFoundError
        { deleted: true, reason: "already_deleted" }
      end

      def rollback
        # Deletion is irreversible; no-op.
      end

      def already_completed?
        step_record.result_snapshot&.dig("deleted") == true
      end
    end
  end
end
