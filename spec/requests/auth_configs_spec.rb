require "rails_helper"

RSpec.describe "AuthConfigs", type: :request do
  let(:user_sub) { "user-sub-123" }
  let!(:org) { create(:organization) }
  let!(:project) { create(:project, :active, organization: org) }

  before { login_as(user_sub) }

  describe "GET /organizations/:org_slug/projects/:slug/auth_config" do
    before do
      membership = create(:org_membership, organization: org, user_sub: user_sub, role: "read")
      create(:project_permission, org_membership: membership, project: project, role: "read")
      create(:project_auth_config, project: project, auth_type: "oidc")
    end

    it "returns 200 with auth config" do
      get "/organizations/#{org.slug}/projects/#{project.slug}/auth_config"
      expect(response).to have_http_status(:ok)
    end

    it "returns 403 for member without project permission" do
      other_project = create(:project, :active, organization: org)
      create(:project_auth_config, project: other_project, auth_type: "oidc")
      get "/organizations/#{org.slug}/projects/#{other_project.slug}/auth_config"
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "PATCH /organizations/:org_slug/projects/:slug/auth_config" do
    before do
      membership = create(:org_membership, organization: org, user_sub: user_sub, role: "write")
      create(:project_permission, org_membership: membership, project: project, role: "write")
      create(:project_auth_config,
             project: project,
             auth_type: "oidc",
             keycloak_client_id: "aap-acme-chatbot-oidc",
             keycloak_client_uuid: "server-owned-uuid")
    end

    it "ignores client attempts to write server-owned keycloak identifiers" do
      original = project.project_auth_config
      patch "/organizations/#{org.slug}/projects/#{project.slug}/auth_config",
            params: { auth_config: {
              keycloak_client_id: "hacker-value",
              keycloak_client_uuid: "hacker-uuid"
            } }

      expect(response).to have_http_status(:ok)
      original.reload
      expect(original.keycloak_client_id).to eq("aap-acme-chatbot-oidc")
      expect(original.keycloak_client_uuid).to eq("server-owned-uuid")
    end

    it "enqueues an update provisioning job when redirect_uris change" do
      expect {
        patch "/organizations/#{org.slug}/projects/#{project.slug}/auth_config",
              params: { auth_config: { redirect_uris: [ "https://new.example.com/callback" ] } }
      }.to change(ProvisioningJob, :count).by(1)

      job = project.provisioning_jobs.order(:id).last
      expect(job.operation).to eq("update")
      expect(job.provisioning_steps.pluck(:name)).to eq(%w[
        keycloak_client_update
        config_server_apply
        health_check
      ])
    end

    it "returns 403 for read-only member" do
      other_project = create(:project, :active, organization: org)
      read_membership = create(:org_membership, organization: org, user_sub: "reader", role: "read")
      create(:project_permission, org_membership: read_membership, project: other_project, role: "read")
      create(:project_auth_config, project: other_project, auth_type: "oidc")
      login_as("reader")
      patch "/organizations/#{org.slug}/projects/#{other_project.slug}/auth_config",
            params: { auth_config: { redirect_uris: [ "https://hack" ] } }
      expect(response).to have_http_status(:forbidden)
    end
  end
end
