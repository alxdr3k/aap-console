require "rails_helper"

RSpec.describe "ConfigVersions", type: :request do
  let(:user_sub) { "user-sub-123" }
  let!(:org) { create(:organization) }
  let!(:project) { create(:project, :active, organization: org) }
  let(:wildcard_headers) { { "ACCEPT" => "*/*" } }
  let(:html_headers) { { "ACCEPT" => "text/html" } }
  let!(:config_version) do
    create(:config_version, project: project, version_id: "v1", change_type: "create",
           changed_by_sub: user_sub, snapshot: { models: [ "gpt-4" ] })
  end

  before { login_as(user_sub) }

  describe "GET /organizations/:org_slug/projects/:slug/config_versions" do
    before do
      membership = create(:org_membership, organization: org, user_sub: user_sub, role: "read")
      create(:project_permission, org_membership: membership, project: project, role: "read")
    end

    let!(:previous_version) do
      create(:config_version,
             project: project,
             version_id: "v0",
             change_type: "create",
             changed_by_sub: user_sub,
             snapshot: { models: [ "claude-sonnet" ] },
             created_at: 1.day.ago)
    end

    it "returns 200 with version list" do
      get "/organizations/#{org.slug}/projects/#{project.slug}/config_versions"
      expect(response).to have_http_status(:ok)
    end

    it "preserves the JSON default for API-like history requests" do
      get "/organizations/#{org.slug}/projects/#{project.slug}/config_versions", headers: wildcard_headers

      expect(response.media_type).to eq("application/json")
      expect(response.parsed_body.first["version_id"]).to eq(config_version.version_id)
    end

    it "renders the browser config history page with diff and rollback context" do
      get "/organizations/#{org.slug}/projects/#{project.slug}/config_versions", headers: html_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("변경 이력")
      expect(response.body).to include("동기 실행")
      expect(response.body).to include(config_version.version_id)
      expect(response.body).to include(previous_version.version_id)
      expect(response.body).to include("Snapshot Diff")
      expect(response.body).to include("--- v0")
      expect(response.body).to include("+++ v1")
      expect(response.body).to include("write 권한 필요")
    end

    it "returns 403 without project permission" do
      other_project = create(:project, :active, organization: org)
      get "/organizations/#{org.slug}/projects/#{other_project.slug}/config_versions"
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /config_versions/:id" do
    before do
      membership = create(:org_membership, organization: org, user_sub: user_sub, role: "read")
      create(:project_permission, org_membership: membership, project: project, role: "read")
    end

    let!(:previous_version) do
      create(:config_version,
             project: project,
             version_id: "v0",
             change_type: "create",
             changed_by_sub: user_sub,
             snapshot: { models: [ "claude-sonnet" ] },
             created_at: 1.day.ago)
    end

    it "returns 200 with version details" do
      get "/config_versions/#{config_version.id}"
      expect(response).to have_http_status(:ok)
    end

    it "renders the browser detail page for turbo frame and direct navigation" do
      get "/config_versions/#{config_version.id}", headers: html_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("config-version-detail")
      expect(response.body).to include("변경 이력으로 돌아가기")
      expect(response.body).to include("--- v0")
      expect(response.body).to include("+++ v1")
    end

    it "returns 403 when no project permission" do
      other_project = create(:project, :active, organization: org)
      other_cv = create(:config_version, project: other_project, version_id: "v2",
                        change_type: "create", changed_by_sub: user_sub)
      get "/config_versions/#{other_cv.id}"
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /config_versions/:id/rollback" do
    before do
      membership = create(:org_membership, organization: org, user_sub: user_sub, role: "write")
      create(:project_permission, org_membership: membership, project: project, role: "write")
    end

    it "reverts Config Server to the target version and records a rollback ConfigVersion" do
      stub_config_server_revert_changes(version: "v-rollback-1")

      expect {
        post "/config_versions/#{config_version.id}/rollback", headers: wildcard_headers
      }.to change(ConfigVersion, :count).by(1)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("completed")
      expect(body["target_version_id"]).to eq("v1")
      expect(body["config_version"]["version_id"]).to eq("v-rollback-1")
      expect(body["diagnostics"]).to include(
        "config_server" => "restored",
        "keycloak" => "not_applicable_no_snapshot",
        "langfuse" => "not_applicable_no_snapshot"
      )

      rollback_version = project.config_versions.order(:created_at).last
      expect(rollback_version.change_type).to eq("rollback")
      expect(rollback_version.snapshot).to eq(config_version.snapshot)
      expect(WebMock).to have_requested(:post, "#{ConfigServerMock::ADMIN_BASE}/changes/revert")
        .with { |request| JSON.parse(request.body)["targetVersion"] == "v1" }
    end

    it "does not enqueue a provisioning job" do
      stub_config_server_revert_changes(version: "v-rollback-1")

      expect {
        post "/config_versions/#{config_version.id}/rollback", headers: wildcard_headers
      }.not_to have_enqueued_job(ProvisioningExecuteJob)
    end

    it "writes an audit log of the completed rollback" do
      stub_config_server_revert_changes(version: "v-rollback-1")

      expect {
        post "/config_versions/#{config_version.id}/rollback", headers: wildcard_headers
      }.to change { AuditLog.where(action: "config.rollback.completed").count }.by(1)
    end

    it "uses a unique idempotency key for each rollback attempt" do
      idempotency_keys = []
      stub_request(:post, "#{ConfigServerMock::ADMIN_BASE}/changes/revert")
        .to_return do |request|
          idempotency_keys << request.headers["X-Idempotency-Key"]
          {
            status: 200,
            body: { version: "v-rollback-#{idempotency_keys.size}" }.to_json,
            headers: { "Content-Type" => "application/json" }
          }
        end

      2.times { post "/config_versions/#{config_version.id}/rollback", headers: wildcard_headers }

      expect(idempotency_keys.size).to eq(2)
      expect(idempotency_keys.uniq.size).to eq(2)
    end

    it "records a new ConfigVersion for each successful rollback even when Config Server returns the same version" do
      stub_config_server_revert_changes(version: "v-rollback-same")

      expect {
        2.times { post "/config_versions/#{config_version.id}/rollback", headers: wildcard_headers }
      }.to change { ConfigVersion.where(project: project, version_id: "v-rollback-same", change_type: "rollback").count }.by(2)
    end

    it "returns 409 when another provisioning job is active" do
      create(:provisioning_job, :in_progress, project: project)

      expect {
        post "/config_versions/#{config_version.id}/rollback", headers: wildcard_headers
      }.to change { AuditLog.where(action: "config.rollback.blocked").count }.by(1)

      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body)["status"]).to eq("blocked")
      expect(a_request(:post, "#{ConfigServerMock::ADMIN_BASE}/changes/revert")).not_to have_been_made
    end

    it "redirects browser rollback back to history and shows diagnostics" do
      stub_config_server_revert_changes(version: "v-rollback-1")

      post "/config_versions/#{config_version.id}/rollback", headers: html_headers

      rollback_version = project.config_versions.order(:created_at).last
      expect(response).to redirect_to(
        organization_project_config_versions_path(org.slug, project.slug, version_id: rollback_version.id)
      )

      follow_redirect!

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("최근 롤백 결과")
      expect(response.body).to include("v-rollback-1 버전으로 롤백되었습니다.")
      expect(response.body).to include("snapshot 없음")
      expect(response.body).to include("Config Server")
    end

    it "returns 502 and records a failed audit log when Config Server revert fails" do
      stub_config_server_revert_changes_failure(status: 500)

      expect {
        post "/config_versions/#{config_version.id}/rollback", headers: wildcard_headers
      }.to change { AuditLog.where(action: "config.rollback.failed").count }.by(1)

      expect(response).to have_http_status(:bad_gateway)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("failed")
      expect(body["diagnostics"]).to include("config_server" => "failed")
    end

    it "redirects browser rollback failures back to history with diagnostics" do
      stub_config_server_revert_changes_failure(status: 500)

      post "/config_versions/#{config_version.id}/rollback", headers: html_headers

      expect(response).to redirect_to(
        organization_project_config_versions_path(org.slug, project.slug, version_id: config_version.id)
      )

      follow_redirect!

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("최근 롤백 결과")
      expect(response.body).to include("Config Server rollback failed")
      expect(response.body).to include("failed")
    end

    it "returns 403 for read-only member" do
      other_project = create(:project, :active, organization: org)
      other_cv = create(:config_version, project: other_project, version_id: "v2",
                        change_type: "create", changed_by_sub: user_sub)
      read_membership = create(:org_membership, organization: org, user_sub: "reader", role: "read")
      create(:project_permission, org_membership: read_membership, project: other_project, role: "read")
      login_as("reader")
      post "/config_versions/#{other_cv.id}/rollback", headers: wildcard_headers
      expect(response).to have_http_status(:forbidden)
    end
  end
end
