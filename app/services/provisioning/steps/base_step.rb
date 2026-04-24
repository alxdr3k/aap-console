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

      # Persist a snapshot describing a side-effect that has already been
      # applied to an external system. Steps must call this immediately
      # after the external call returns success and before any local DB
      # write that could raise. RollbackRunner uses the persisted snapshot
      # to undo external state even if the surrounding step record never
      # reaches `completed`.
      def record_external_side_effect(snapshot)
        step_record.update!(result_snapshot: snapshot)
        snapshot
      end

      private

      attr_reader :step_record, :project, :params
    end
  end
end
