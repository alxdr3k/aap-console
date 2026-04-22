module Provisioning
  module Steps
    class AppRegistryDeregister < BaseStep
      def execute
        client = ConfigServerClient.new
        client.notify_app_registry(
          action: "delete",
          app_data: { app_id: project.app_id },
          idempotency_key: "deregister-#{step_record.id}-#{project.app_id}"
        )

        { deregistered: true, app_id: project.app_id }
      rescue BaseClient::NotFoundError
        { deregistered: true, reason: "already_deregistered" }
      end

      def rollback
        # Deregistration is irreversible; no-op.
      end

      def already_completed?
        step_record.result_snapshot&.dig("deregistered") == true
      end
    end
  end
end
