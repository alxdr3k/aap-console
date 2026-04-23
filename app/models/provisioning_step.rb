class ProvisioningStep < ApplicationRecord
  belongs_to :provisioning_job

  enum :status, {
    pending: 0,
    in_progress: 1,
    completed: 2,
    failed: 3,
    retrying: 4,
    skipped: 5,
    rolled_back: 6,
    rollback_failed: 7
  }

  validates :name, presence: true, uniqueness: { scope: :provisioning_job_id }
  validates :step_order, presence: true
end
