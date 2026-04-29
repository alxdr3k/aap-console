require "rails_helper"

RSpec.describe "Api::V1::ProjectApiKeys", type: :request do
  let!(:org) { create(:organization, slug: "acme") }
  let!(:project) { create(:project, :active, organization: org, slug: "chatbot") }
  let(:token) { "pak-#{SecureRandom.alphanumeric(40)}" }
  let!(:project_api_key) do
    create(
      :project_api_key,
      project: project,
      name: "runtime-key",
      token_digest: ProjectApiKey.digest_token(token),
      token_prefix: token.first(ProjectApiKey::TOKEN_PREFIX_LENGTH)
    )
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("CONSOLE_INBOUND_API_KEY").and_return("test-inbound-key")
  end

  describe "POST /api/v1/project_api_keys/verify" do
    it "verifies an active token and updates last_used_at" do
      expect {
        post "/api/v1/project_api_keys/verify",
             params: { token: token },
             headers: { "Authorization" => "Bearer test-inbound-key" }
      }.to change { project_api_key.reload.last_used_at }.from(nil)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to include("valid" => true)
      expect(body.fetch("project_api_key")).to include(
        "id" => project_api_key.id,
        "name" => "runtime-key",
        "token_prefix" => project_api_key.token_prefix
      )
      expect(body.fetch("project")).to include(
        "app_id" => project.app_id,
        "org" => "acme",
        "slug" => "chatbot"
      )
    end

    it "rejects revoked tokens" do
      project_api_key.update!(revoked_at: Time.current)

      post "/api/v1/project_api_keys/verify",
           params: { token: token },
           headers: { "Authorization" => "Bearer test-inbound-key" }

      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)).to include("valid" => false)
    end

    it "rejects tokens for non-serving projects" do
      project.update!(status: :provision_failed)

      expect {
        post "/api/v1/project_api_keys/verify",
             params: { token: token },
             headers: { "Authorization" => "Bearer test-inbound-key" }
      }.not_to change { project_api_key.reload.last_used_at }

      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)).to include("valid" => false)
    end

    it "returns 401 without the inbound API key" do
      post "/api/v1/project_api_keys/verify", params: { token: token }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
