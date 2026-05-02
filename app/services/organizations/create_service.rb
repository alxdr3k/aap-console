module Organizations
  class CreateService
    def initialize(params:, current_user_sub:, langfuse_client: LangfuseClient.new, keycloak_client: KeycloakClient.new)
      @params = params.to_h.symbolize_keys
      @current_user_sub = current_user_sub
      @langfuse_client = langfuse_client
      @keycloak_client = keycloak_client
    end

    def call
      if @params[:initial_admin_user_sub].present? && @params[:initial_admin_user_sub] != @current_user_sub
        begin
          @keycloak_client.get_user(user_sub: @params[:initial_admin_user_sub])
        rescue BaseClient::NotFoundError
          return Result.failure("Initial admin user not found")
        rescue BaseClient::ApiError => e
          return Result.failure("Keycloak error: #{e.message}")
        end
      end

      organization = Organization.new(
        name: @params[:name],
        description: @params[:description],
        slug: @params[:slug]
      )

      return Result.failure(organization.errors.full_messages.to_sentence) unless organization.valid?

      langfuse_org = @langfuse_client.create_organization(name: organization.name)
      langfuse_org_id = langfuse_org["id"]
      organization.langfuse_org_id = langfuse_org_id

      begin
        ActiveRecord::Base.transaction do
          organization.save!
          organization.org_memberships.create!(
            user_sub: initial_admin_user_sub,
            role: "admin",
            invited_at: Time.current,
            joined_at: initial_admin_joined_at
          )
          AuditLog.create!(
            organization: organization,
            user_sub: @current_user_sub,
            action: "org.create",
            resource_type: "Organization",
            resource_id: organization.id.to_s,
            details: { name: organization.name, initial_admin_user_sub: initial_admin_user_sub }
          )
        end
      rescue ActiveRecord::RecordInvalid => e
        # Compensate the Langfuse side-effect so we don't leak orphan orgs
        # into Langfuse when the Console-side transaction fails. Rollback is
        # best-effort: a failure here is logged but does not mask the
        # original DB error.
        compensate_langfuse(langfuse_org_id)
        return Result.failure(e.message)
      end

      Result.success(organization)
    rescue BaseClient::ApiError => e
      Result.failure("Langfuse error: #{e.message}")
    end

    private

    def initial_admin_user_sub
      @initial_admin_user_sub ||= @params[:initial_admin_user_sub].presence || @current_user_sub
    end

    def initial_admin_joined_at
      Time.current if initial_admin_user_sub == @current_user_sub
    end

    def compensate_langfuse(langfuse_org_id)
      return unless langfuse_org_id
      @langfuse_client.delete_organization(id: langfuse_org_id)
    rescue BaseClient::ApiError => e
      Rails.logger.error(
        "[Organizations::CreateService] Failed to compensate Langfuse org " \
        "#{langfuse_org_id} after DB save failure: #{e.class}: #{e.message}"
      )
    end
  end
end
