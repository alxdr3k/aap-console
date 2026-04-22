module RequestHelpers
  def login_as(user_sub, realm_roles: [])
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:keycloak] = OmniAuth::AuthHash.new(
      provider: "keycloak",
      uid: user_sub,
      info: { email: "#{user_sub}@example.com", name: "Test User" },
      extra: {
        raw_info: {
          "sub" => user_sub,
          "realm_access" => { "roles" => realm_roles }
        }
      }
    )
    get "/auth/keycloak/callback"
  end
end

RSpec.configure do |config|
  config.include RequestHelpers, type: :request
  config.include LangfuseMock, type: :request
  config.include KeycloakMock, type: :request
  config.include ConfigServerMock, type: :request
end
