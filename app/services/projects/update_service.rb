module Projects
  class UpdateService
    # Fields that require external propagation via provisioning
    AUTH_CONFIG_FIELDS = %i[redirect_uris post_logout_redirect_uris].freeze
    LITELLM_CONFIG_FIELDS = %i[models guardrails s3_retention_days].freeze
    EXTERNAL_FIELDS = (AUTH_CONFIG_FIELDS + LITELLM_CONFIG_FIELDS).freeze

    def initialize(project:, params:, current_user_sub:)
      @project = project
      @params = params
      @current_user_sub = current_user_sub
    end

    def call
      return Result.failure("Cannot update a deleted project") if @project.deleted?

      needs_provisioning = EXTERNAL_FIELDS.any? { |field| @params.key?(field) }

      if needs_provisioning
        return Result.failure("Another provisioning job is in progress") if active_job_exists?
      end

      ActiveRecord::Base.transaction do
        update_project_metadata if metadata_params.any?

        if needs_provisioning
          @project.update!(status: :update_pending)
          provisioning_job = @project.provisioning_jobs.create!(
            operation: "update",
            status: :pending
          )
          Provisioning::StepSeeder.call!(provisioning_job)
          ProvisioningExecuteJob.perform_later(
            provisioning_job.id,
            **@params.slice(*EXTERNAL_FIELDS).merge(current_user_sub: @current_user_sub)
          )
        end

        AuditLog.create!(
          organization: @project.organization,
          project: @project,
          user_sub: @current_user_sub,
          action: "project.update",
          resource_type: "Project",
          resource_id: @project.id.to_s,
          details: { changed_fields: @params.keys }
        )
      end

      Result.success(@project)
    rescue ActiveRecord::RecordInvalid => e
      Result.failure(e.message)
    end

    private

    def update_project_metadata
      @project.update!(metadata_params)
    end

    def metadata_params
      @params.slice(:name, :description)
    end

    def active_job_exists?
      @project.provisioning_jobs.where(status: ProvisioningJob::ACTIVE_STATUSES).exists?
    end
  end
end
