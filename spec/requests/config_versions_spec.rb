require "rails_helper"

RSpec.describe "ConfigVersions", type: :request do
  let(:user_sub) { "user-sub-123" }
  let!(:org) { create(:organization) }
  let!(:project) { create(:project, :active, organization: org) }
  let!(:config_version) do
    create(:config_version, project: project, version_id: "v1", change_type: "create",
           changed_by_sub: user_sub, snapshot: { models: ["gpt-4"] })
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

    it "triggers rollback provisioning and returns see_other" do
      stub_config_server_revert_changes(version: "v2")
      post "/config_versions/#{config_version.id}/rollback"
      expect(response).to have_http_status(:see_other)
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
