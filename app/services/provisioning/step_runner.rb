module Provisioning
  class StepRunner
    # Upper bound (in seconds) on how long a single worker thread is allowed
    # to sleep waiting for an inline retry. Anything longer is deferred via
    # SolidQueue re-enqueue so the worker is freed up.
    MAX_INLINE_RETRY_SLEEP = 8

    # Number of retry attempts during which inline sleep is still permitted
    # (backoff sequence is 2, 4, 8, 16, 32 seconds).
    MAX_INLINE_RETRIES = 3

    def initialize(step:, provisioning_job:, params: {})
      @step = step
      @provisioning_job = provisioning_job
      @params = params
    end

    def execute
      @step.update!(status: :in_progress, started_at: Time.current)
      broadcast_step_update

      step_impl = build_step_impl

      if step_impl.already_completed?
        @step.update!(status: :skipped, completed_at: Time.current)
        broadcast_step_update
        return { status: :completed, step: @step, ephemeral_params: {} }
      end

      attempt_execute(step_impl, retry_count: @step.retry_count || 0)
    end

    private

    def attempt_execute(step_impl, retry_count: 0)
      raw_result = step_impl.execute
      ephemeral = raw_result.is_a?(Hash) ? (raw_result.delete(:_ephemeral) || {}) : {}
      @step.update!(
        status: :completed,
        completed_at: Time.current,
        result_snapshot: raw_result,
        retry_count: retry_count
      )
      broadcast_step_update
      { status: :completed, step: @step, ephemeral_params: ephemeral }
    rescue => e
      handle_failure(step_impl, e, retry_count)
    end

    def handle_failure(step_impl, error, retry_count)
      max_retries = @step.max_retries || 3

      if retry_count >= max_retries
        return record_final_failure(error, retry_count)
      end

      interval = backoff_interval(retry_count)

      if interval <= MAX_INLINE_RETRY_SLEEP && retry_count < MAX_INLINE_RETRIES
        @step.update!(status: :retrying, retry_count: retry_count + 1, error_message: error.message)
        broadcast_step_update
        sleep interval
        attempt_execute(step_impl, retry_count: retry_count + 1)
      else
        # Deferred retry: free the worker. The Orchestrator is expected to
        # re-enqueue ProvisioningExecuteJob with `wait: interval`. The
        # step will be picked up again in :retrying status and attempted
        # from the top of #execute.
        @step.update!(status: :retrying, retry_count: retry_count + 1, error_message: error.message)
        broadcast_step_update
        { status: :deferred, step: @step, retry_count: retry_count + 1, retry_in: interval }
      end
    end

    def record_final_failure(error, retry_count)
      @step.update!(
        status: :failed,
        completed_at: Time.current,
        retry_count: retry_count,
        error_message: error.message
      )
      broadcast_step_update
      { status: :failed, step: @step, error: error }
    end

    def backoff_interval(retry_count)
      [ 2 ** (retry_count + 1), 32 ].min
    end

    def build_step_impl
      klass = step_class_for(@step.name)
      klass.new(
        step_record: @step,
        project: @provisioning_job.project,
        params: @params
      )
    end

    def step_class_for(name)
      class_name = name.split("_").map(&:capitalize).join
      "Provisioning::Steps::#{class_name}".constantize
    end

    def broadcast_step_update
      ActionCable.server.broadcast(
        "provisioning_job_#{@provisioning_job.id}",
        { type: "step_update", step_id: @step.id, status: @step.status, error: @step.error_message }
      )
    end
  end
end
