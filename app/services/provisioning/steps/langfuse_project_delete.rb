module Provisioning
  module Steps
    class LangfuseProjectDelete < BaseStep
      def execute
        create_step = step_record.provisioning_job.project
                                 .provisioning_jobs
                                 .joins(:provisioning_steps)
                                 .where(provisioning_steps: { name: "langfuse_project_create", status: :completed })
                                 .order("provisioning_jobs.created_at DESC")
                                 .first
                                 &.provisioning_steps
                                 &.find_by(name: "langfuse_project_create")

        langfuse_project_id = create_step&.result_snapshot&.dig("langfuse_project_id")
        return { deleted: true, reason: "no_langfuse_project" } unless langfuse_project_id

        langfuse = LangfuseClient.new
        langfuse.delete_project(id: langfuse_project_id)

        { deleted: true, langfuse_project_id: langfuse_project_id }
      rescue BaseClient::NotFoundError
        { deleted: true, reason: "already_deleted" }
      end

      def rollback
        # Deletion is irreversible; no-op.
      end

      def already_completed?
        step_record.result_snapshot&.dig("deleted") == true
      end
    end
  end
end
