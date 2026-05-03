module Api
  module V1
    class AppsController < BaseController
      def index
        # Config Server uses this registry as the source of truth for app
        # authentication. Expose active projects and update_pending projects:
        # update_pending keeps serving the previous known-good external
        # resources while an update job is running. In-flight creates, failed,
        # deleting, and deleted projects must not be advertised.
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
    end
  end
end
