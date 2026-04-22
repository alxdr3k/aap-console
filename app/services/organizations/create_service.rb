module Organizations
  class CreateService
    def initialize(params:, current_user_sub:, langfuse_client: LangfuseClient.new)
      @params = params
      @current_user_sub = current_user_sub
      @langfuse_client = langfuse_client
    end

    def call
      organization = Organization.new(
        name: @params[:name],
        description: @params[:description],
        slug: @params[:slug]
      )

      return Result.failure(organization.errors.full_messages.to_sentence) unless organization.valid?

      langfuse_org = @langfuse_client.create_organization(name: organization.name)
      organization.langfuse_org_id = langfuse_org["id"]

      ActiveRecord::Base.transaction do
        organization.save!
        organization.org_memberships.create!(
          user_sub: @current_user_sub,
          role: "admin",
          invited_at: Time.current,
          joined_at: Time.current
        )
        AuditLog.create!(
          organization: organization,
          user_sub: @current_user_sub,
          action: "org.create",
          resource_type: "Organization",
          resource_id: organization.id.to_s,
          details: { name: organization.name }
        )
      end

      Result.success(organization)
    rescue ActiveRecord::RecordInvalid => e
      Result.failure(e.message)
    rescue BaseClient::ApiError => e
      Result.failure("Langfuse error: #{e.message}")
    end
  end
end
