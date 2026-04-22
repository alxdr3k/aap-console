require "rails_helper"

RSpec.describe "LitellmConfigs", type: :request do
  let(:user_sub) { "user-sub-123" }
  let!(:org) { create(:organization) }
  let!(:project) { create(:project, :active, organization: org) }

  before { login_as(user_sub) }

  describe "GET /organizations/:org_slug/projects/:slug/litellm_config" do
    before do
      membership = create(:org_membership, organization: org, user_sub: user_sub, role: "read")
      create(:project_permission, org_membership: membership, project: project, role: "read")
    end

    it "returns 200" do
      get "/organizations/#{org.slug}/projects/#{project.slug}/litellm_config"
      expect(response).to have_http_status(:ok)
    end

    it "returns 403 for member without project permission" do
      other_project = create(:project, :active, organization: org)
      get "/organizations/#{org.slug}/projects/#{other_project.slug}/litellm_config"
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "PATCH /organizations/:org_slug/projects/:slug/litellm_config" do
    before do
      membership = create(:org_membership, organization: org, user_sub: user_sub, role: "write")
      create(:project_permission, org_membership: membership, project: project, role: "write")
    end

    it "enqueues update provisioning and redirects" do
      patch "/organizations/#{org.slug}/projects/#{project.slug}/litellm_config",
            params: { litellm_config: { models: [ "azure-gpt4" ], s3_retention_days: 90 } }
      expect(response).to have_http_status(:see_other)
      expect(project.provisioning_jobs.where(operation: "update").count).to eq(1)
    end

    it "returns 403 for read-only member" do
      other_project = create(:project, :active, organization: org)
      read_membership = create(:org_membership, organization: org, user_sub: "reader", role: "read")
      create(:project_permission, org_membership: read_membership, project: other_project, role: "read")
      login_as("reader")
      patch "/organizations/#{org.slug}/projects/#{other_project.slug}/litellm_config",
            params: { litellm_config: { models: [ "azure-gpt4" ] } }
      expect(response).to have_http_status(:forbidden)
    end
  end
end
