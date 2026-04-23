module Projects
  class CreateService
    def initialize(organization:, params:, current_user_sub:)
      @organization = organization
      @params = params
      @current_user_sub = current_user_sub
    end

    def call
      project = @organization.projects.new(
        name: @params[:name],
        description: @params[:description],
        slug: @params[:slug],
        status: :provisioning
      )

      return Result.failure(project.errors.full_messages.to_sentence) unless project.valid?

      ActiveRecord::Base.transaction do
        project.save!

        project.create_project_auth_config!(
          auth_type: @params[:auth_type]
        )

        provisioning_job = project.provisioning_jobs.create!(
          operation: "create",
          status: :pending
        )
        Provisioning::StepSeeder.call!(provisioning_job)

        AuditLog.create!(
          organization: @organization,
          project: project,
          user_sub: @current_user_sub,
          action: "project.create",
          resource_type: "Project",
          resource_id: project.id.to_s,
          details: {
            name: project.name,
            app_id: project.app_id,
            auth_type: @params[:auth_type]
          }
        )

        ProvisioningExecuteJob.perform_later(
          provisioning_job.id,
          auth_type: @params[:auth_type],
          models: @params[:models],
          s3_retention_days: @params[:s3_retention_days],
          current_user_sub: @current_user_sub
        )
      end

      Result.success(project)
    rescue ActiveRecord::RecordInvalid => e
      Result.failure(e.message)
    end
  end
end
