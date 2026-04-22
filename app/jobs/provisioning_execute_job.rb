class ProvisioningExecuteJob < ApplicationJob
  queue_as :provisioning

  limits_concurrency to: 1, key: ->(job_id, **) { ProvisioningJob.find(job_id).project_id }

  retry_on StandardError, attempts: 2
  discard_on ActiveRecord::RecordNotFound

  def perform(provisioning_job_id, **kwargs)
    provisioning_job = ProvisioningJob.find(provisioning_job_id)
    Provisioning::Orchestrator.new(
      provisioning_job: provisioning_job,
      params: kwargs.except(:current_user_sub),
      current_user_sub: kwargs[:current_user_sub]
    ).run
  end
end
