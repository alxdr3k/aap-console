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

# CSRF posture for OmniAuth initiation (`POST /auth/:provider`):
#
# omniauth-rails_csrf_protection rejects GET-initiated auth requests so that
# a third party cannot embed an <img src="/auth/keycloak"> in a malicious
# page and silently start an authentication flow. We must therefore only
# allow POST, and the Console initiates auth by rendering an auto-submitting
# form bound to the Rails CSRF token (see ApplicationController and
# app/views/sessions/login.html.erb).
#
# The `silence_get_warning = true` from the original config was hiding a
# real CSRF risk and is removed.
OmniAuth.config.allowed_request_methods = [ :post ]
