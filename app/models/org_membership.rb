class OrgMembership < ApplicationRecord
  belongs_to :organization
  has_many :project_permissions, dependent: :destroy

  ROLES = %w[admin write read].freeze

  validates :user_sub, presence: true
  validates :role, presence: true, inclusion: { in: ROLES }
  validates :user_sub, uniqueness: { scope: :organization_id }

  def admin?
    role == "admin"
  end
end
