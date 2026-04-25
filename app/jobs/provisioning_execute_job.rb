class ProvisioningExecuteJob < ApplicationJob
  queue_as :provisioning

  limits_concurrency to: 1, key: ->(job_id, **) { ProvisioningJob.find(job_id).project_id }

  retry_on StandardError, attempts: 2
  discard_on ActiveRecord::RecordNotFound

  def perform(provisioning_job_id, **kwargs)
    provisioning_job = ProvisioningJob.find(provisioning_job_id)

    # Terminal-state guard. A late-arriving execution (e.g. a deferred-retry
    # re-enqueue that fires after the job was rolled back, or a duplicate
    # SolidQueue claim) must not re-enter the orchestrator and start
    # transitioning the job back to in_progress. The set of terminal statuses
    # mirrors ProvisioningJob::TERMINAL_STATUSES.
    if ProvisioningJob::TERMINAL_STATUSES.include?(provisioning_job.status)
      Rails.logger.info(
        "[ProvisioningExecuteJob] skipping job=#{provisioning_job.id} in terminal status=#{provisioning_job.status}"
      )
      return
    end

    # Job args are the fast path. If they're empty (manual retry from the
    # controller, or worker re-enqueue that lost its params), fall back to
    # provisioning_jobs.input_snapshot — the durable record of the original
    # external inputs. This is what makes manual retry safe across crashes.
    job_params = kwargs.except(:current_user_sub)
    if job_params.empty? && provisioning_job.input_snapshot.present?
      job_params = provisioning_job.input_snapshot.symbolize_keys
    end

    Provisioning::Orchestrator.new(
      provisioning_job: provisioning_job,
      params: job_params,
      current_user_sub: kwargs[:current_user_sub]
    ).run
  end
end
