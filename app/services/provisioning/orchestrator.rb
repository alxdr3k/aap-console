module Provisioning
  class Orchestrator
    def initialize(provisioning_job:, params: {}, current_user_sub: nil)
      @provisioning_job = provisioning_job
      @params = params
      @current_user_sub = current_user_sub
    end

    def run
      @provisioning_job.update!(status: :in_progress, started_at: Time.current)
      step_groups = load_steps

      step_groups.each do |steps|
        results = run_step_group(steps)
        if results.any? { |r| r[:status] == :failed }
          rollback_and_fail
          return
        end
        results.each { |r| @params.merge!(r[:ephemeral_params] || {}) }
      end

      complete_successfully
    rescue => e
      @provisioning_job.update!(
        status: :failed,
        error_message: e.message,
        completed_at: Time.current
      )
      raise
    end

    private

    def load_steps
      steps = @provisioning_job.provisioning_steps.order(:step_order)
      steps.group_by(&:step_order).values
    end

    def run_step_group(steps)
      if steps.size == 1
        [ run_single_step(steps.first) ]
      else
        threads = steps.map do |step|
          Thread.new { run_single_step(step) }
        end
        threads.map(&:value)
      end
    end

    def run_single_step(step)
      runner = StepRunner.new(step: step, provisioning_job: @provisioning_job, params: @params)
      runner.execute
    end

    def rollback_and_fail
      @provisioning_job.update!(status: :rolling_back)
      rollback_runner = RollbackRunner.new(provisioning_job: @provisioning_job)
      if rollback_runner.run
        @provisioning_job.update!(status: :rolled_back, completed_at: Time.current)
      else
        @provisioning_job.update!(status: :rollback_failed, completed_at: Time.current)
      end

      project = @provisioning_job.project
      if @provisioning_job.operation == "create"
        project.update!(status: :provision_failed)
      end
    end

    def complete_successfully
      warnings = @provisioning_job.provisioning_steps
                                  .where(name: "health_check")
                                  .where(status: :failed)
                                  .any?

      final_status = warnings ? :completed_with_warnings : :completed
      @provisioning_job.update!(status: final_status, completed_at: Time.current)

      project = @provisioning_job.project
      case @provisioning_job.operation
      when "create", "update"
        project.update!(status: :active)
      when "delete"
        project.update!(status: :deleted)
      end

      broadcast_completion
    end

    def broadcast_completion
      ActionCable.server.broadcast(
        "provisioning_job_#{@provisioning_job.id}",
        { type: "job_completed", status: @provisioning_job.status }
      )
    end
  end
end
