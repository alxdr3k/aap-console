class ProvisioningJobsCleanupJob < ApplicationJob
  queue_as :default

  RETENTION_DAYS = 180
  DEFAULT_BATCH_SIZE = 500
  CLEANUP_STATUSES = %w[completed completed_with_warnings rolled_back].freeze
  PRESERVED_STATUSES = %w[failed rollback_failed].freeze

  def perform(retention_days: RETENTION_DAYS, batch_size: DEFAULT_BATCH_SIZE)
    cutoff = retention_days.to_i.days.ago
    deleted_count = 0

    cleanup_scope(cutoff).find_each(batch_size: batch_size.to_i) do |provisioning_job|
      provisioning_job.destroy!
      deleted_count += 1
    end

    Rails.logger.info(
      "[ProvisioningJobsCleanupJob] deleted=#{deleted_count} cutoff=#{cutoff.iso8601} " \
      "retention_days=#{retention_days.to_i}"
    )

    {
      deleted: deleted_count,
      cutoff: cutoff.iso8601,
      retention_days: retention_days.to_i,
      cleanup_statuses: CLEANUP_STATUSES,
      preserved_statuses: PRESERVED_STATUSES
    }
  end

  private

  def cleanup_scope(cutoff)
    ProvisioningJob
      .where(status: CLEANUP_STATUSES)
      .where("COALESCE(completed_at, updated_at) < ?", cutoff)
  end
end
