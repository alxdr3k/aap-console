module Provisioning
  class RollbackRunner
    def initialize(provisioning_job:)
      @provisioning_job = provisioning_job
    end

    def run
      completed_steps = @provisioning_job.provisioning_steps
                                         .where(status: [ :completed, :skipped ])
                                         .order(step_order: :desc)

      completed_steps.each do |step|
        rollback_step(step)
      end

      true
    rescue => e
      Rails.logger.error "Rollback failed for job #{@provisioning_job.id}: #{e.message}"
      false
    end

    private

    def rollback_step(step)
      step_impl = build_step_impl(step)
      step_impl.rollback
      step.update!(status: :rolled_back)
    rescue => e
      step.update!(status: :rollback_failed, error_message: e.message)
      raise
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
      class_name = name.split("_").map(&:capitalize).join
      "Provisioning::Steps::#{class_name}".constantize
    end
  end
end
