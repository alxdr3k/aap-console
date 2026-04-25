class ProjectAuthConfig < ApplicationRecord
  belongs_to :project

  AUTH_TYPES = %w[oidc saml oauth pak].freeze
  KEYCLOAK_BACKED_TYPES = %w[oidc saml oauth].freeze

  validates :auth_type, presence: true, inclusion: { in: AUTH_TYPES }

  before_validation :assign_keycloak_client_id, on: :create

  private

  # PRD §5.4 / CLAUDE.md naming: `aap-{org-id}-{project-id}-{protocol}`.
  # Persisted as soon as the row is created so downstream provisioning steps
  # (KeycloakClientCreate, AppRegistryRegister) always have a stable identifier
  # — regardless of which entry-point built the auth_config. PAK has no
  # Keycloak counterpart, so we leave the column null.
  def assign_keycloak_client_id
    return if keycloak_client_id.present?
    return unless KEYCLOAK_BACKED_TYPES.include?(auth_type)
    return unless project&.organization&.slug && project&.slug

    self.keycloak_client_id = "aap-#{project.organization.slug}-#{project.slug}-#{auth_type}"
  end
end
