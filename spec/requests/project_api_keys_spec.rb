require "rails_helper"

RSpec.describe "ProjectApiKeys", type: :request do
  let(:user_sub) { "user-sub-123" }
  let!(:org) { create(:organization) }
  let!(:project) { create(:project, :active, organization: org) }
  let(:path) { "/organizations/#{org.slug}/projects/#{project.slug}/project_api_keys" }
  let(:html_headers) { { "ACCEPT" => "text/html" } }
  let(:turbo_headers) { { "ACCEPT" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" } }
  let(:wildcard_headers) { { "ACCEPT" => "*/*" } }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }

  before do
    login_as(user_sub)
    allow(Rails).to receive(:cache).and_return(cache)
  end

  describe "GET /organizations/:org_slug/projects/:project_slug/project_api_keys" do
    it "lists project API keys for a reader without exposing digests" do
      grant_project_role("read")
      active_key = create(:project_api_key, project: project)
      revoked_key = create(:project_api_key, :revoked, project: project)

      get path, headers: wildcard_headers

      expect(response).to have_http_status(:ok)
      keys = JSON.parse(response.body)
      expect(keys.pluck("id")).to match_array([ active_key.id, revoked_key.id ])
      expect(keys.first).to include("token_prefix")
      expect(keys.first).not_to have_key("token_digest")
      expect(keys.first).not_to have_key("token")
    end

    it "redirects browser requests to the auth config page" do
      grant_project_role("read")
      create(:project_auth_config, project: project, auth_type: "oidc")

      get path, headers: html_headers

      expect(response).to redirect_to(organization_project_auth_config_path(org.slug, project.slug))
    end

    it "returns 403 without project permission" do
      create(:org_membership, organization: org, user_sub: user_sub, role: "read")

      get path, headers: wildcard_headers

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /organizations/:org_slug/projects/:project_slug/project_api_keys" do
    it "issues a PAK once and stores only the digest and prefix" do
      grant_project_role("write")

      expect {
        post path, params: { project_api_key: { name: "staging-ci" } }, headers: wildcard_headers
      }.to change(ProjectApiKey, :count).by(1)
        .and change { AuditLog.where(action: "project_api_key.create").count }.by(1)

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      token = body.fetch("token")
      key = ProjectApiKey.find(body.fetch("id"))

      expect(token).to start_with("pak-")
      expect(key.name).to eq("staging-ci")
      expect(key.token_digest).to eq(ProjectApiKey.digest_token(token))
      expect(key.token_prefix).to eq(token.first(ProjectApiKey::TOKEN_PREFIX_LENGTH))
      expect(body.fetch("token_prefix")).to eq(key.token_prefix)
      expect(body).not_to have_key("token_digest")

      audit = AuditLog.where(action: "project_api_key.create").last
      expect(audit.details).to include("name" => "staging-ci", "token_prefix" => key.token_prefix)
      expect(audit.details.to_s).not_to include(token)
    end

    it "redirects browser issue requests back to auth config with a reveal panel" do
      grant_project_role("write")
      create(:project_auth_config, project: project, auth_type: "oidc")

      post path, params: { project_api_key: { name: "browser-ci" } }, headers: html_headers

      expect(response).to redirect_to(organization_project_auth_config_path(org.slug, project.slug))

      follow_redirect!

      expect(response).to have_http_status(:ok)
      expect(response.headers["Cache-Control"]).to eq("no-store")
      expect(response.body).to include("일회성 PAK")
      expect(response.body).to include("browser-ci")
      expect(response.body).to include("pak-")
    end

    it "treats Turbo browser issue requests as the auth config redirect flow" do
      grant_project_role("write")
      create(:project_auth_config, project: project, auth_type: "oidc")

      post path, params: { project_api_key: { name: "turbo-ci" } }, headers: turbo_headers

      expect(response).to redirect_to(organization_project_auth_config_path(org.slug, project.slug))
    end

    it "rejects duplicate names within the same project" do
      grant_project_role("write")
      create(:project_api_key, project: project, name: "staging-ci")

      post path, params: { project_api_key: { name: "staging-ci" } }, headers: wildcard_headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body).fetch("errors").first).to include("Name has already been taken")
    end

    it "returns 403 for read-only members" do
      grant_project_role("read")

      post path, params: { project_api_key: { name: "read-only" } }, headers: wildcard_headers

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "DELETE /organizations/:org_slug/projects/:project_slug/project_api_keys/:id" do
    let!(:project_api_key) { create(:project_api_key, project: project) }

    before { grant_project_role("write") }

    it "soft-revokes a PAK and writes an audit event" do
      expect {
        delete "#{path}/#{project_api_key.id}", headers: wildcard_headers
      }.to change { project_api_key.reload.revoked_at }.from(nil)
        .and change { AuditLog.where(action: "project_api_key.revoke").count }.by(1)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.fetch("revoked_at")).to be_present
      expect(ProjectApiKey.exists?(project_api_key.id)).to be(true)
    end

    it "redirects browser revoke requests back to auth config" do
      create(:project_auth_config, project: project, auth_type: "oidc")

      delete "#{path}/#{project_api_key.id}", headers: html_headers

      expect(response).to redirect_to(organization_project_auth_config_path(org.slug, project.slug))

      follow_redirect!

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(project_api_key.name)
      expect(response.body).to include("revoked")
    end

    it "treats Turbo browser revoke requests as the auth config redirect flow" do
      create(:project_auth_config, project: project, auth_type: "oidc")

      delete "#{path}/#{project_api_key.id}", headers: turbo_headers

      expect(response).to redirect_to(organization_project_auth_config_path(org.slug, project.slug))
    end

    it "does not write duplicate revoke audit events for an already revoked PAK" do
      project_api_key.update!(revoked_at: Time.current)

      expect {
        delete "#{path}/#{project_api_key.id}", headers: wildcard_headers
      }.not_to change { AuditLog.where(action: "project_api_key.revoke").count }

      expect(response).to have_http_status(:ok)
    end
  end

  def grant_project_role(role)
    membership_role = role == "read" ? "read" : "write"
    membership = create(:org_membership, organization: org, user_sub: user_sub, role: membership_role)
    create(:project_permission, org_membership: membership, project: project, role: role)
  end
end
