module Organizations
  class DestroyService
    def initialize(organization:, current_user_sub:, langfuse_client: LangfuseClient.new)
      @organization = organization
      @current_user_sub = current_user_sub
      @langfuse_client = langfuse_client
    end

    def call
      non_deleted_projects = @organization.projects.where.not(status: :deleted)

      non_deleted_projects.each do |project|
        result = Projects::DestroyService.new(project: project, current_user_sub: @current_user_sub).call
        return result if result.failure?
      end

      # When projects are being asynchronously deleted, defer org destruction.
      # The org will be cleaned up once all project provisioning jobs complete.
      return Result.success if non_deleted_projects.any?

      if @organization.langfuse_org_id.present?
        @langfuse_client.delete_organization(id: @organization.langfuse_org_id)
      end

      AuditLog.create!(
        organization: @organization,
        user_sub: @current_user_sub,
        action: "org.destroy",
        resource_type: "Organization",
        resource_id: @organization.id.to_s,
        details: { name: @organization.name }
      )

      @organization.destroy!
      Result.success
    rescue BaseClient::ApiError => e
      Result.failure("External service error: #{e.message}")
    rescue ActiveRecord::RecordNotDestroyed => e
      Result.failure(e.message)
    end
  end
end
