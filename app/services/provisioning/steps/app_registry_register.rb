module Provisioning
  module Steps
    class AppRegistryRegister < BaseStep
      def execute
        client = ConfigServerClient.new
        app_data = build_app_data

        client.notify_app_registry(
          action: "register",
          app_data: app_data,
          idempotency_key: idempotency_key("register")
        )

        { registered: true, app_id: project.app_id }
      end

      def rollback
        return unless step_record.result_snapshot&.dig("registered")

        client = ConfigServerClient.new
        client.notify_app_registry(
          action: "delete",
          app_data: { app_id: project.app_id },
          idempotency_key: idempotency_key("deregister")
        )
      end

      def already_completed?
        step_record.result_snapshot&.dig("registered") == true
      end

      private

      def build_app_data
        auth_config = project.project_auth_config
        {
          app_id: project.app_id,
          app_name: auth_config&.keycloak_client_id,
          org: project.organization.slug,
          project: project.slug,
          service: "litellm",
          permissions: {
            config_read: true,
            env_vars_read: true,
            resolve_secrets: true
          }
        }
      end

      def idempotency_key(action)
        "#{action}-#{step_record.id}-#{project.app_id}"
      end
    end
  end
end
