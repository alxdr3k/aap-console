class ProvisioningJob < ApplicationRecord
  belongs_to :project
  has_many :provisioning_steps, dependent: :destroy
  has_many :config_versions, dependent: :nullify

  OPERATIONS = %w[create update delete].freeze

  enum :status, {
    pending: 0,
    in_progress: 1,
    completed: 2,
    completed_with_warnings: 3,
    failed: 4,
    retrying: 5,
    rolling_back: 6,
    rolled_back: 7,
    rollback_failed: 8
  }

  validates :operation, presence: true, inclusion: { in: OPERATIONS }

  ACTIVE_STATUSES = %w[pending in_progress retrying rolling_back].freeze
  TERMINAL_STATUSES = %w[completed completed_with_warnings failed rolled_back rollback_failed].freeze

  def active?
    ACTIVE_STATUSES.include?(status)
  end
end
