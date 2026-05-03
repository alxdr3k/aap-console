module Api
  module V1
    class ProjectApiKeysController < BaseController
      def verify
        result = ::ProjectApiKeys::VerifyService.new(token: params[:token]).call

        if result.success?
          project_api_key = result.data
          project = project_api_key.project
          organization = project.organization

          render json: {
            valid: true,
            project_api_key: {
              id: project_api_key.id,
              name: project_api_key.name,
              token_prefix: project_api_key.token_prefix,
              last_used_at: project_api_key.last_used_at
            },
            project: {
              app_id: project.app_id,
              org: organization.slug,
              slug: project.slug
            }
          }
        else
          render json: { valid: false, error: result.error }, status: :not_found
        end
      end
    end
  end
end
