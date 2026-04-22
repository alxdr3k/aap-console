require "rails_helper"

RSpec.describe "Sessions", type: :request do
  describe "GET /auth/keycloak/callback" do
    let(:user_sub) { "user-sub-abc123" }
    let(:auth_hash) do
      OmniAuth::AuthHash.new(
        provider: "keycloak",
        uid: user_sub,
        info: { email: "user@example.com", name: "Test User" },
        extra: {
          raw_info: {
            "sub" => user_sub,
            "realm_access" => { "roles" => ["user"] }
          }
        }
      )
    end

    before do
      OmniAuth.config.test_mode = true
      OmniAuth.config.mock_auth[:keycloak] = auth_hash
    end

    it "stores user_sub and realm_roles in session and redirects" do
      get "/auth/keycloak/callback"
      expect(session[:user_sub]).to eq(user_sub)
      expect(session[:realm_roles]).to eq(["user"])
      expect(response).to redirect_to("/organizations")
    end

    context "when realm roles include super_admin" do
      before do
        auth_hash.extra.raw_info["realm_access"] = { "roles" => ["super_admin"] }
      end

      it "stores super_admin in realm_roles" do
        get "/auth/keycloak/callback"
        expect(session[:realm_roles]).to include("super_admin")
      end
    end
  end

  describe "DELETE /auth/logout" do
    before { post "/auth/keycloak", env: { "omniauth.auth" => OmniAuth::AuthHash.new } }

    it "clears the session" do
      get "/auth/keycloak/callback"
      delete "/auth/logout"
      expect(session[:user_sub]).to be_nil
    end

    it "redirects to root" do
      delete "/auth/logout"
      expect(response).to redirect_to("/")
    end
  end
end
