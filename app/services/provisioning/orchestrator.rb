module Provisioning
  class Orchestrator
    # Steps whose failure should NOT trigger rollback. A failure here is
    # surfaced as a warning and the job is marked completed_with_warnings.
    # See HLD §5.1 ("complete_successfully" warning path) and FR-9.
    WARNING_STEPS = %w[health_check].freeze

    def initialize(provisioning_job:, params: {}, current_user_sub: nil)
      @provisioning_job = provisioning_job
      @params = params
      @current_user_sub = current_user_sub
    end

    def run
      @provisioning_job.update!(status: :in_progress, started_at: Time.current)
      step_groups = load_steps

      if step_groups.empty?
        fail_without_rollback("No provisioning steps seeded for job #{@provisioning_job.id}")
        return
      end

      warning_failures = []

      step_groups.each do |steps|
        results = safely_run_group(steps)

        deferred = results.select { |r| r[:status] == :deferred }
        if deferred.any?
          schedule_retry(deferred.map { |r| r[:retry_in] }.compact.max || 0)
          return
        end

        fatal_failures = results.select { |r| r[:status] == :failed && fatal?(r[:step]) }
        if fatal_failures.any?
          rollback_and_fail(fatal_failures.first[:error]&.message)
          return
        end

        warning_failures.concat(results.select { |r| r[:status] == :failed })
        results.each { |r| @params.merge!(r[:ephemeral_params] || {}) }
      end

      complete_successfully(warning_failures)
    rescue => e
      rollback_and_fail(e.message)
    end

    private

    def load_steps
      steps = @provisioning_job.provisioning_steps.order(:step_order)
      steps.group_by(&:step_order).values
    end

    # Wraps run_step_group so that any exception escaping a thread or the
    # single-step path is normalized into a :failed result. This keeps the
    # orchestration layer from bypassing rollback when a step raises instead
    # of returning cleanly.
    def safely_run_group(steps)
      results = run_step_group(steps)
      results.map { |r| r.is_a?(Hash) ? r : normalize_result(r) }
    rescue => e
      # Unexpected raise from thread.value re-raising inside Thread.new.
      # Mark any in_progress step of this group as failed and surface as a
      # fatal result so the outer loop triggers rollback.
      first_step = steps.first
      [ { status: :failed, step: first_step, error: e } ]
    end

    def run_step_group(steps)
      if steps.size == 1
        [ run_single_step_safely(steps.first) ]
      else
        threads = steps.map do |step|
          Thread.new { run_single_step_safely(step) }
        end
        threads.map(&:value)
      end
    end

    # Runs one step inside the Rails executor + a reserved DB connection so
    # parallel threads do not leak connections or bypass Rails request state.
    # Any raise is normalized to a :failed result instead of propagating.
    def run_single_step_safely(step)
      Rails.application.executor.wrap do
        ActiveRecord::Base.connection_pool.with_connection do
          StepRunner.new(
            step: step,
            provisioning_job: @provisioning_job,
            params: @params.dup
          ).execute
        end
      end
    rescue => e
      begin
        step.update(
          status: :failed,
          error_message: e.message,
          completed_at: Time.current
        )
      rescue StandardError
        # If even the status update fails, we still surface the original error.
      end
      { status: :failed, step: step, error: e }
    end

    def normalize_result(result)
      { status: :failed, step: nil, error: StandardError.new("unexpected result: #{result.inspect}") }
    end

    def fatal?(step)
      return true if step.nil?
      !WARNING_STEPS.include?(step.name)
    end

    def rollback_and_fail(error_message = nil)
      @provisioning_job.update!(status: :rolling_back, error_message: error_message)
      rollback_runner = RollbackRunner.new(provisioning_job: @provisioning_job)
      if rollback_runner.run
        @provisioning_job.update!(status: :rolled_back, completed_at: Time.current)
      else
        @provisioning_job.update!(status: :rollback_failed, completed_at: Time.current)
      end

      transition_project_on_failure
      broadcast_completion
    end

    # Used when we cannot rollback because nothing was done (e.g. no steps
    # seeded). We transition to failed directly rather than rolling_back.
    def fail_without_rollback(error_message)
      @provisioning_job.update!(
        status: :failed,
        error_message: error_message,
        completed_at: Time.current
      )
      transition_project_on_failure
      broadcast_completion
    end

    def transition_project_on_failure
      project = @provisioning_job.project
      case @provisioning_job.operation
      when "create"
        project.update!(status: :provision_failed) unless project.provision_failed?
      when "update"
        # Only restore to active when the rollback succeeded. A rollback_failed
        # job leaves the project in update_pending so operators know drift exists.
        project.update!(status: :active) if @provisioning_job.rolled_back? && !project.active?
      when "delete"
        # Project remains in its prior state (:deleting). Admin must retry.
      end
    end

    def complete_successfully(warning_failures = [])
      warnings = warning_failures.map do |r|
        step_name = r[:step]&.name
        { step: step_name, message: r[:error]&.message || r[:step]&.error_message }
      end

      final_status = warnings.any? ? :completed_with_warnings : :completed
      update_attrs = { status: final_status, completed_at: Time.current }
      update_attrs[:warnings] = warnings if warnings.any?
      @provisioning_job.update!(update_attrs)

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

    # Called when one or more steps return :deferred. The job is marked
    # :retrying and the ProvisioningExecuteJob is re-enqueued to run after
    # the longest deferred interval has elapsed. The worker thread exits
    # immediately so it can serve other provisioning jobs meanwhile.
    #
    # IMPORTANT: the original external params (models, redirect_uris, etc.)
    # must be forwarded to the next enqueue. ProvisioningExecuteJob#perform
    # rebuilds the Orchestrator from job args, so dropping them here would
    # mean the retry attempt sees an empty params hash and turns an auth or
    # LiteLLM update into a no-op.
    def schedule_retry(wait_seconds)
      @provisioning_job.update!(status: :retrying)
      ProvisioningExecuteJob
        .set(wait: wait_seconds.seconds)
        .perform_later(
          @provisioning_job.id,
          **@params.merge(current_user_sub: @current_user_sub)
        )
    end
  end
end
