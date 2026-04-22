class ProjectApiKey < ApplicationRecord
  belongs_to :project

  validates :name, presence: true
  validates :token_digest, presence: true, uniqueness: true
  validates :token_prefix, presence: true
  validates :name, uniqueness: { scope: :project_id }

  scope :active, -> { where(revoked_at: nil) }

  def revoked?
    revoked_at.present?
  end
end
