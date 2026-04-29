require "rails_helper"

RSpec.describe "ConfigVersions", type: :request do
  let(:user_sub) { "user-sub-123" }
  let!(:org) { create(:organization) }
  let!(:project) { create(:project, :active, organization: org) }
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

    it "returns 200 with version list" do
      get "/organizations/#{org.slug}/projects/#{project.slug}/config_versions"
      expect(response).to have_http_status(:ok)
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

    it "returns 200 with version details" do
      get "/config_versions/#{config_version.id}"
      expect(response).to have_http_status(:ok)
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
        post "/config_versions/#{config_version.id}/rollback"
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
        post "/config_versions/#{config_version.id}/rollback"
      }.not_to have_enqueued_job(ProvisioningExecuteJob)
    end

    it "writes an audit log of the completed rollback" do
      stub_config_server_revert_changes(version: "v-rollback-1")

      expect {
        post "/config_versions/#{config_version.id}/rollback"
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

      2.times { post "/config_versions/#{config_version.id}/rollback" }

      expect(idempotency_keys.size).to eq(2)
      expect(idempotency_keys.uniq.size).to eq(2)
    end

    it "returns 409 when another provisioning job is active" do
      create(:provisioning_job, :in_progress, project: project)

      expect {
        post "/config_versions/#{config_version.id}/rollback"
      }.to change { AuditLog.where(action: "config.rollback.blocked").count }.by(1)

      expect(response).to have_http_status(:conflict)
      expect(a_request(:post, "#{ConfigServerMock::ADMIN_BASE}/changes/revert")).not_to have_been_made
    end

    it "returns 502 and records a failed audit log when Config Server revert fails" do
      stub_config_server_revert_changes_failure(status: 500)

      expect {
        post "/config_versions/#{config_version.id}/rollback"
      }.to change { AuditLog.where(action: "config.rollback.failed").count }.by(1)

      expect(response).to have_http_status(:bad_gateway)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("failed")
      expect(body["diagnostics"]).to include("config_server" => "failed")
    end

    it "returns 403 for read-only member" do
      other_project = create(:project, :active, organization: org)
      other_cv = create(:config_version, project: other_project, version_id: "v2",
                        change_type: "create", changed_by_sub: user_sub)
      read_membership = create(:org_membership, organization: org, user_sub: "reader", role: "read")
      create(:project_permission, org_membership: read_membership, project: other_project, role: "read")
      login_as("reader")
      post "/config_versions/#{other_cv.id}/rollback"
      expect(response).to have_http_status(:forbidden)
    end
  end
end
