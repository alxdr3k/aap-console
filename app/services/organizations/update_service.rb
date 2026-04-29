module Organizations
  class UpdateService
    UPDATABLE_FIELDS = %i[name description].freeze

    def initialize(organization:, params:, current_user_sub:, langfuse_client: LangfuseClient.new)
      @organization = organization
      @params = params.to_h.symbolize_keys.slice(*UPDATABLE_FIELDS)
      @current_user_sub = current_user_sub
      @langfuse_client = langfuse_client
    end

    def call
      old_name = @organization.name
      @organization.assign_attributes(@params)

      return Result.failure(@organization.errors.full_messages.to_sentence) unless @organization.valid?

      sync_langfuse_name if langfuse_name_changed?

      begin
        ActiveRecord::Base.transaction do
          changed_fields = @organization.changed.map(&:to_s)
          @organization.save!

          AuditLog.create!(
            organization: @organization,
            user_sub: @current_user_sub,
            action: "org.update",
            resource_type: "Organization",
            resource_id: @organization.id.to_s,
            details: { name: @organization.name, changed_fields: changed_fields }
          )
        end
      rescue ActiveRecord::RecordInvalid => e
        compensate_langfuse_name(old_name)
        return Result.failure(e.message)
      end

      Result.success(@organization)
    rescue BaseClient::ApiError => e
      Result.failure("External service error: #{e.message}")
    end

    private

    def langfuse_name_changed?
      @organization.langfuse_org_id.present? && @organization.name_changed?
    end

    def sync_langfuse_name
      @langfuse_client.update_organization(
        id: @organization.langfuse_org_id,
        name: @organization.name
      )
    end

    def compensate_langfuse_name(old_name)
      return unless @organization.langfuse_org_id.present?
      return if old_name == @organization.name

      @langfuse_client.update_organization(
        id: @organization.langfuse_org_id,
        name: old_name
      )
    rescue BaseClient::ApiError => e
      Rails.logger.error(
        "[Organizations::UpdateService] Failed to compensate Langfuse org " \
        "#{@organization.langfuse_org_id} after DB save failure: #{e.class}: #{e.message}"
      )
    end
  end
end
