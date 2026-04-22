module Provisioning
  module Steps
    class DbCleanup < BaseStep
      def execute
        ActiveRecord::Base.transaction do
          project.project_permissions.destroy_all
          project.project_api_keys.destroy_all
          project.update!(status: :deleted)
        end

        { cleaned_up: true }
      end

      def rollback
        # DB cleanup is the last step in delete pipeline; no rollback.
      end

      def already_completed?
        project.deleted?
      end
    end
  end
end
