class ConfigVersion < ApplicationRecord
  belongs_to :project
  belongs_to :provisioning_job, optional: true

  CHANGE_TYPES = %w[create update delete rollback].freeze

  validates :version_id, presence: true
  validates :change_type, presence: true, inclusion: { in: CHANGE_TYPES }
  validates :changed_by_sub, presence: true
end
