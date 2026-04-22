class ProjectPermission < ApplicationRecord
  belongs_to :org_membership
  belongs_to :project

  ROLES = %w[write read].freeze

  validates :role, presence: true, inclusion: { in: ROLES }
  validates :org_membership_id, uniqueness: { scope: :project_id }
end
