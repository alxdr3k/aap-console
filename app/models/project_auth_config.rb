class ProjectAuthConfig < ApplicationRecord
  belongs_to :project

  AUTH_TYPES = %w[oidc saml oauth pak].freeze

  validates :auth_type, presence: true, inclusion: { in: AUTH_TYPES }
end
