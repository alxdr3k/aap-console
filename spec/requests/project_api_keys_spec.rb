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

    it "renders browser issue requests in-band with the reveal panel" do
      grant_project_role("write")
      create(:project_auth_config, project: project, auth_type: "oidc")

      post path, params: { project_api_key: { name: "browser-ci" } }, headers: html_headers

      expect(response).to have_http_status(:ok)
      expect(response.headers["Cache-Control"]).to eq("no-store")
      expect(response.body).to include("일회성 PAK")
      expect(response.body).to include("browser-ci")
      expect(response.body).to include("pak-")
    end

    it "renders Turbo PAK issue requests in-band to prevent shared-cache reveal races" do
      grant_project_role("write")
      create(:project_auth_config, project: project, auth_type: "oidc")

      post path, params: { project_api_key: { name: "turbo-ci" } }, headers: turbo_headers

      expect(response).to have_http_status(:ok)
      expect(response.headers["Cache-Control"]).to eq("no-store")
      expect(response.body).to include("turbo-ci")
      expect(response.body).to include("일회성 PAK")
    end

    it "renders the PAK in-band when shared reveal cache persistence fails on plain HTML" do
      grant_project_role("write")
      create(:project_auth_config, project: project, auth_type: "oidc")
      allow(cache).to receive(:write).and_return(false)

      expect {
        post path, params: { project_api_key: { name: "in-band-ci" } }, headers: html_headers
      }.not_to change { AuditLog.where(action: "project_api_key.revoke").count }

      issued = project.project_api_keys.find_by!(name: "in-band-ci")
      expect(issued.revoked_at).to be_nil

      expect(response).to have_http_status(:ok)
      expect(response.headers["Cache-Control"]).to eq("no-store")
      expect(response.body).to include("일회성 PAK")
      expect(response.body).to include("표시 캐시 저장에 실패")
      expect(response.body).to include("in-band-ci")
      expect(response.body).to match(/pak-[A-Za-z0-9_-]+/)
    end

    it "renders the PAK in-band when the reveal cache raises during persistence" do
      grant_project_role("write")
      create(:project_auth_config, project: project, auth_type: "oidc")
      allow(ProjectApiKeys::RevealCache).to receive(:write).and_raise("cache backend down")
      allow(Rails.logger).to receive(:error)

      post path, params: { project_api_key: { name: "raise-ci" } }, headers: html_headers

      issued = project.project_api_keys.find_by!(name: "raise-ci")
      expect(issued.revoked_at).to be_nil
      expect(response).to have_http_status(:ok)
      expect(response.headers["Cache-Control"]).to eq("no-store")
      expect(response.body).to include("표시 캐시 저장에 실패")
      expect(response.body).to include("raise-ci")
    end

    it "drops a stale cached reveal payload before rendering the in-band fallback" do
      grant_project_role("write")
      create(:project_auth_config, project: project, auth_type: "oidc")
      stale_key = create(:project_api_key, project: project, name: "stale-reveal")
      ProjectApiKeys::RevealCache.write(project, project_api_key: stale_key, token: "pak-stale-secret")
      allow(cache).to receive(:write).and_return(false)

      post path, params: { project_api_key: { name: "fresh-key" } }, headers: html_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("fresh-key")
      expect(response.body).not_to include("pak-stale-secret")

      # The stale cache must not survive the fallback; a follow-up GET should
      # not resurface the previous token in place of the freshly issued one.
      cached_after = ProjectApiKeys::RevealCache.read(project)
      expect(cached_after.dig("secrets", "project_api_key", "value")).to be_nil
    end

    it "fails closed when both reveal cache delete and reconcile-write fail" do
      grant_project_role("write")
      create(:project_auth_config, project: project, auth_type: "oidc")
      allow(ProjectApiKeys::RevealCache).to receive(:write).and_raise("cache backend down")
      allow(ProjectApiKeys::RevealCache).to receive(:delete).and_raise("cache backend down")
      allow(Rails.logger).to receive(:error)

      post path, params: { project_api_key: { name: "fail-closed" } }, headers: html_headers

      expect(response).to redirect_to(organization_project_auth_config_path(org.slug, project.slug))
      issued = project.project_api_keys.find_by!(name: "fail-closed")
      expect(issued.revoked_at).to be_nil
      follow_redirect!
      expect(response.body).to include("표시 캐시 정리에 실패")
    end

    it "renders the older request's PAK in-band when cache holds a newer concurrent reveal" do
      grant_project_role("write")
      create(:project_auth_config, project: project, auth_type: "oidc")

      # Simulate a concurrent issuance whose cache.write succeeded with a PAK
      # id strictly higher than the request we're about to fall back. The
      # falling-back request must (a) leave the newer reveal intact, and
      # (b) display its OWN PAK plaintext in-band so the operator does not
      # see the other request's secret instead of theirs.
      newer_id = 999_999
      cache.write(
        ProjectApiKeys::RevealCache.send(:cache_key, project),
        {
          "organization_id" => project.organization_id,
          "project_id" => project.id,
          "secrets" => {
            "project_api_key" => {
              "project_api_key_id" => newer_id,
              "value" => "pak-newer-secret",
              "name" => "newer-concurrent",
              "token_prefix" => "pak"
            }
          }
        }
      )

      post path, params: { project_api_key: { name: "older-loser" } }, headers: html_headers

      issued = project.project_api_keys.find_by!(name: "older-loser")
      expect(issued.id).to be < newer_id
      expect(issued.revoked_at).to be_nil

      # In-band rendering of the older request's PAK plaintext.
      expect(response).to have_http_status(:ok)
      expect(response.headers["Cache-Control"]).to eq("no-store")
      expect(response.body).to include("older-loser")
      expect(response.body).not_to include("pak-newer-secret")

      # The cache must continue to surface the newer PAK reveal.
      cached = ProjectApiKeys::RevealCache.read(project)
      expect(cached.dig("secrets", "project_api_key", "project_api_key_id")).to eq(newer_id)
      expect(cached.dig("secrets", "project_api_key", "value")).to eq("pak-newer-secret")
    end

    it "overwrites a malformed stale cache entry that hides from a naive blank? check" do
      grant_project_role("write")
      create(:project_auth_config, project: project, auth_type: "oidc")
      # Simulate a stale cache that survives delete (false return) and whose
      # payload is shaped so `dig("secrets", "project_api_key")` returns nil
      # while a non-empty `secrets` hash still lives under the cache key.
      malformed = {
        "organization_id" => project.organization_id,
        "project_id" => project.id,
        "secrets" => { "stale_blob" => "leftover" }
      }
      cache.write(ProjectApiKeys::RevealCache.send(:cache_key, project), malformed)
      allow(ProjectApiKeys::RevealCache).to receive(:delete).and_return(false)
      original_write = ProjectApiKeys::RevealCache.method(:write)
      attempt = 0
      allow(ProjectApiKeys::RevealCache).to receive(:write) do |*args, **kwargs|
        attempt += 1
        attempt == 1 ? false : original_write.call(*args, **kwargs)
      end

      post path, params: { project_api_key: { name: "overwrite-malformed" } }, headers: html_headers

      issued = project.project_api_keys.find_by!(name: "overwrite-malformed")
      expect(issued.revoked_at).to be_nil
      # Reconcile-write succeeded on the retry; the controller renders in-band.
      expect(response).to have_http_status(:ok)
      cached_after = ProjectApiKeys::RevealCache.read(project)
      expect(cached_after.dig("secrets", "project_api_key", "project_api_key_id")).to eq(issued.id)
      expect(cached_after.dig("secrets", "stale_blob")).to be_nil
    end

    it "fails closed when the request format is non-HTML and the reveal cache fails" do
      grant_project_role("write")
      create(:project_auth_config, project: project, auth_type: "oidc")
      allow(cache).to receive(:write).and_return(false)

      # Drive the controller through a turbo_stream-only Accept so the in-band
      # render path stays scoped to plain HTML responses only. A Turbo Stream
      # consumer cannot receive a secret-bearing body outside the no-store
      # HTML page lifecycle.
      post path,
           params: { project_api_key: { name: "stream-ci" } },
           headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

      expect(response).to redirect_to(organization_project_auth_config_path(org.slug, project.slug))
      issued = project.project_api_keys.find_by!(name: "stream-ci")
      expect(issued.revoked_at).to be_nil
    end

    it "does not persist the plaintext PAK in the browser session cookie when the cache fails" do
      grant_project_role("write")
      create(:project_auth_config, project: project, auth_type: "oidc")
      allow(cache).to receive(:write).and_return(false)

      post path, params: { project_api_key: { name: "no-cookie" } }, headers: html_headers

      cookie_jar = response.cookies
      session_cookie = cookie_jar["_aap_console_session"] || cookie_jar.values.compact.find { |value| value.is_a?(String) }
      expect(session_cookie.to_s).not_to include("project_api_key_reveal_fallbacks")
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

    it "keeps the current reveal payload when revoking a different key" do
      create(:project_auth_config, project: project, auth_type: "oidc")
      stale_key = create(:project_api_key, project: project, name: "stale-ci")

      post path, params: { project_api_key: { name: "fresh-ci" } }, headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("fresh-ci")
      expect(response.body).to include("일회성 PAK")

      delete "#{path}/#{stale_key.id}", headers: html_headers
      follow_redirect!

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("fresh-ci")
      expect(response.body).to include("일회성 PAK")
      expect(response.body).to include("pak-")
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
