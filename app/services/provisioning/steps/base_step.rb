module Provisioning
  module Steps
    class BaseStep
      def initialize(step_record:, project:, params: {})
        @step_record = step_record
        @project = project
        @params = params
      end

      # Returns a Hash of snapshot data on success. Raises on failure.
      def execute
        raise NotImplementedError, "#{self.class}#execute is not implemented"
      end

      # Uses step_record.result_snapshot to undo the executed action.
      def rollback
        raise NotImplementedError, "#{self.class}#rollback is not implemented"
      end

      # Returns true if the external resource already exists (idempotency check).
      def already_completed?
        raise NotImplementedError, "#{self.class}#already_completed? is not implemented"
      end

      private

      attr_reader :step_record, :project, :params
    end
  end
end
