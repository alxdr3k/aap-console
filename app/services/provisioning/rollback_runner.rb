module Provisioning
  class RollbackRunner
    def initialize(provisioning_job:)
      @provisioning_job = provisioning_job
    end

    def run
      candidate_steps = @provisioning_job.provisioning_steps
                                         .order(step_order: :desc)
                                         .select { |s| eligible_for_rollback?(s) }

      # Best-effort: continue rolling back lower-order steps even when a
      # higher-order step's rollback raises. Halting on the first failure
      # would leave independent external side effects (e.g. app registry
      # entries) behind for operators to discover manually after a
      # cross-project IdentityMismatch on Keycloak rollback.
      any_failed = false
      candidate_steps.each do |step|
        any_failed = true unless rollback_step(step)
      end

      !any_failed
    rescue => e
      Rails.logger.error("Rollback runner uncaught exception for job #{@provisioning_job.id}: #{e.class}: #{e.message}")
      false

    end

    private

    # A step is rolled back when:
    # - it cleanly completed (the typical case), OR
    # - it was skipped (idempotent re-entry — treat as completed), OR
    # - it failed but left a result_snapshot, meaning the external side
    #   effect succeeded before a later (local DB) write raised. Without
    #   this branch, partial side effects would leak out of the all-or-
    #   nothing pipeline (HLD §5.1, FR-7.2).
    def eligible_for_rollback?(step)
      case step.status
      when "completed", "skipped"
        true
      when "failed", "retrying"
        step.result_snapshot.present?
      else
        false
      end
    end

    def rollback_step(step)
      step_impl = build_step_impl(step)
      step_impl.rollback
      step.update!(status: :rolled_back)
      true
    rescue => e
      Rails.logger.error(
        "Rollback failed for job #{@provisioning_job.id} step #{step.id}: #{e.class}: #{e.message}"
      )
      step.update!(status: :rollback_failed, error_message: e.message)
      false
    end

    def build_step_impl(step)
      klass = step_class_for(step.name)
      klass.new(
        step_record: step,
        project: @provisioning_job.project,
        params: {}
      )
    end

    def step_class_for(name)
      Provisioning::StepRunner::STEP_CLASSES.fetch(name) { raise ArgumentError, "Unknown provisioning step: #{name.inspect}" }
    end
  end
end
