class ProjectApiKey < ApplicationRecord
  belongs_to :project

  TOKEN_PREFIX_LENGTH = 8

  validates :name, presence: true
  validates :token_digest, presence: true, uniqueness: true
  validates :token_prefix, presence: true
  validates :name, uniqueness: { scope: :project_id }

  scope :active, -> { where(revoked_at: nil) }

  def self.digest_token(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  def revoked?
    revoked_at.present?
  end
end
