module Api
  module V1
    class AppsController < ActionController::API
      before_action :authenticate_inbound_api_key!

      def index
        # Config Server uses this registry as the source of truth for app
        # authentication. Only expose projects that have completed
        # provisioning (status :active or :completed_with_warnings via
        # provision_failed/update_pending excluded). In-flight, failed, or
        # deleting projects must not be advertised, otherwise Config Server
        # would mint cache entries for apps whose external resources do not
        # yet (or no longer) exist.
        projects = Project.where(status: [ :active, :update_pending ])
                          .includes(:organization, :project_auth_config)

        apps = projects.map do |project|
          {
            app_id: project.app_id,
            app_name: project.project_auth_config&.keycloak_client_id,
            org: project.organization.slug,
            project: project.slug,
            service: "litellm",
            permissions: {
              config_read: true,
              env_vars_read: true,
              resolve_secrets: true
            },
            created_at: project.created_at
          }
        end

        render json: { apps: apps }
      end

      private

      def authenticate_inbound_api_key!
        token = extract_bearer_token
        expected = ENV["CONSOLE_INBOUND_API_KEY"]

        if expected.blank? || token != expected
          render json: { error: "Unauthorized" }, status: :unauthorized
        end
      end

      def extract_bearer_token
        auth_header = request.headers["Authorization"]
        return nil unless auth_header&.start_with?("Bearer ")
        auth_header.sub("Bearer ", "")
      end
    end
  end
end
