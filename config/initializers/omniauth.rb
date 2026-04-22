Rails.application.config.middleware.use OmniAuth::Builder do
  provider :keycloak_openid,
           ENV.fetch("KEYCLOAK_CLIENT_ID", "aap-console"),
           ENV.fetch("KEYCLOAK_CLIENT_SECRET", "changeme"),
           client_options: {
             site: ENV.fetch("KEYCLOAK_URL", "http://localhost:8080"),
             realm: ENV.fetch("KEYCLOAK_REALM", "aap")
           },
           name: "keycloak"
end

OmniAuth.config.allowed_request_methods = [:post, :get]
OmniAuth.config.silence_get_warning = true
