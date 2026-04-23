module Projects
  class DestroyService
    def initialize(project:, current_user_sub:)
      @project = project
      @current_user_sub = current_user_sub
    end

    def call
      return Result.failure("Project already deleted") if @project.deleted?
      return Result.failure("Another provisioning job is in progress") if active_job_exists?

      ActiveRecord::Base.transaction do
        @project.update!(status: :deleting)

        provisioning_job = @project.provisioning_jobs.create!(
          operation: "delete",
          status: :pending
        )
        Provisioning::StepSeeder.call!(provisioning_job)

        AuditLog.create!(
          organization: @project.organization,
          project: @project,
          user_sub: @current_user_sub,
          action: "project.destroy",
          resource_type: "Project",
          resource_id: @project.id.to_s,
          details: { name: @project.name, app_id: @project.app_id }
        )

        ProvisioningExecuteJob.perform_later(provisioning_job.id, current_user_sub: @current_user_sub)
      end

      Result.success(@project)
    rescue ActiveRecord::RecordInvalid => e
      Result.failure(e.message)
    end

    private

    def active_job_exists?
      @project.provisioning_jobs.where(status: ProvisioningJob::ACTIVE_STATUSES).exists?
    end
  end
end
