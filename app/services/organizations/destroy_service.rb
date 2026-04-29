module Organizations
  class DestroyService
    def initialize(organization:, current_user_sub:, langfuse_client: LangfuseClient.new)
      @organization = organization
      @current_user_sub = current_user_sub
      @langfuse_client = langfuse_client
    end

    def call
      non_deleted_projects = @organization.projects.where.not(status: :deleted)
      blocking_project = blocking_project_with_active_job(non_deleted_projects)

      if blocking_project
        return Result.failure("Another provisioning job is in progress for project #{blocking_project.slug}")
      end

      non_deleted_projects.each do |project|
        next if project.deleting?

        result = Projects::DestroyService.new(project: project, current_user_sub: @current_user_sub).call
        return result if result.failure?
      end

      if non_deleted_projects.any?
        pending_projects = pending_project_summaries
        audit_deferred_destroy!(pending_projects)
        enqueue_finalizer
        return Result.success(deferred: true, pending_projects: pending_projects)
      end

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

    private

    def enqueue_finalizer
      OrganizationDestroyFinalizeJob
        .set(wait: OrganizationDestroyFinalizeJob::RETRY_DELAY)
        .perform_later(@organization.id, current_user_sub: @current_user_sub)
    end

    def blocking_project_with_active_job(projects)
      projects.find do |project|
        next false if project.deleting?

        project.provisioning_jobs.where(status: ProvisioningJob::ACTIVE_STATUSES).exists?
      end
    end

    def audit_deferred_destroy!(pending_projects)
      AuditLog.create!(
        organization: @organization,
        user_sub: @current_user_sub,
        action: "org.destroy.requested",
        resource_type: "Organization",
        resource_id: @organization.id.to_s,
        details: {
          name: @organization.name,
          pending_project_count: pending_projects.size,
          pending_projects: pending_projects
        }
      )
    end

    def pending_project_summaries
      @organization.projects.where.not(status: :deleted).includes(:provisioning_jobs).map do |project|
        latest_delete_job = project.provisioning_jobs
                                   .select { |job| job.operation == "delete" }
                                   .max_by(&:created_at)

        {
          id: project.id,
          slug: project.slug,
          status: project.status,
          provisioning_job_id: latest_delete_job&.id
        }
      end
    end
  end
end
