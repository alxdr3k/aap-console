class AuditLog < ApplicationRecord
  belongs_to :organization, optional: true
  belongs_to :project, optional: true

  validates :user_sub, presence: true
  validates :action, presence: true
  validates :resource_type, presence: true
end
