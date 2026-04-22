FactoryBot.define do
  factory :project_auth_config do
    project
    auth_type { "oidc" }
    keycloak_client_id { "aap-org-#{SecureRandom.hex(4)}-oidc" }
    keycloak_client_uuid { SecureRandom.uuid }

    trait :oidc do
      auth_type { "oidc" }
    end

    trait :saml do
      auth_type { "saml" }
      keycloak_client_id { "aap-org-#{SecureRandom.hex(4)}-saml" }
    end

    trait :oauth do
      auth_type { "oauth" }
      keycloak_client_id { "aap-org-#{SecureRandom.hex(4)}-oauth" }
    end

    trait :pak do
      auth_type { "pak" }
      keycloak_client_id { nil }
      keycloak_client_uuid { nil }
    end
  end
end
