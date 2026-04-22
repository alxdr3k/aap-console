require "rails_helper"

RSpec.describe "Projects", type: :request do
  let(:user_sub) { "user-sub-123" }
  let!(:org) { create(:organization) }

  before { login_as(user_sub) }

  describe "GET /organizations/:org_slug/projects" do
    let!(:project) { create(:project, :active, organization: org) }

    before { create(:org_membership, organization: org, user_sub: user_sub, role: "read") }

    it "returns 200 with accessible projects" do
      get "/organizations/#{org.slug}/projects"
      expect(response).to have_http_status(:ok)
    end

    it "returns 403 for non-member" do
      other_org = create(:organization)
      get "/organizations/#{other_org.slug}/projects"
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /organizations/:org_slug/projects" do
    before { create(:org_membership, organization: org, user_sub: user_sub, role: "admin") }

    it "creates a project and redirects to provisioning job" do
      post "/organizations/#{org.slug}/projects",
           params: { project: { name: "My Project", description: "desc", auth_type: "oidc" } }
      expect(response).to have_http_status(:see_other)
      project = Project.last
      expect(response).to redirect_to(provisioning_job_path(project.provisioning_jobs.last))
    end

    it "returns 422 on validation failure" do
      post "/organizations/#{org.slug}/projects",
           params: { project: { name: "A", auth_type: "oidc" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 403 for non-admin" do
      create(:org_membership, organization: org, user_sub: "reader", role: "read")
      login_as("reader")
      post "/organizations/#{org.slug}/projects",
           params: { project: { name: "New", auth_type: "oidc" } }
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /organizations/:org_slug/projects/:slug" do
    let!(:project) { create(:project, :active, organization: org) }

    context "as org admin" do
      before { create(:org_membership, organization: org, user_sub: user_sub, role: "admin") }

      it "returns 200" do
        get "/organizations/#{org.slug}/projects/#{project.slug}"
        expect(response).to have_http_status(:ok)
      end
    end

    context "as member with project permission" do
      before do
        membership = create(:org_membership, organization: org, user_sub: user_sub, role: "read")
        create(:project_permission, org_membership: membership, project: project, role: "read")
      end

      it "returns 200" do
        get "/organizations/#{org.slug}/projects/#{project.slug}"
        expect(response).to have_http_status(:ok)
      end
    end

    it "returns 403 for member without project permission" do
      create(:org_membership, organization: org, user_sub: user_sub, role: "read")
      get "/organizations/#{org.slug}/projects/#{project.slug}"
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "PATCH /organizations/:org_slug/projects/:slug" do
    let!(:project) { create(:project, :active, organization: org) }

    before do
      membership = create(:org_membership, organization: org, user_sub: user_sub, role: "write")
      create(:project_permission, org_membership: membership, project: project, role: "write")
    end

    it "updates the project and returns 200" do
      patch "/organizations/#{org.slug}/projects/#{project.slug}",
            params: { project: { name: "Updated Name" } }
      expect(response).to have_http_status(:ok)
      expect(project.reload.name).to eq("Updated Name")
    end

    it "returns 403 for read-only member" do
      other_project = create(:project, :active, organization: org)
      read_membership = create(:org_membership, organization: org, user_sub: "reader", role: "read")
      create(:project_permission, org_membership: read_membership, project: other_project, role: "read")
      login_as("reader")
      patch "/organizations/#{org.slug}/projects/#{other_project.slug}",
            params: { project: { name: "Hack" } }
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "DELETE /organizations/:org_slug/projects/:slug" do
    let!(:project) { create(:project, :active, organization: org) }

    before { create(:org_membership, organization: org, user_sub: user_sub, role: "admin") }

    it "starts delete provisioning and redirects" do
      delete "/organizations/#{org.slug}/projects/#{project.slug}"
      expect(response).to have_http_status(:see_other)
      expect(project.reload.status).to eq("deleting")
    end

    it "returns 403 for non-admin" do
      membership = create(:org_membership, organization: org, user_sub: "writer", role: "write")
      create(:project_permission, org_membership: membership, project: project, role: "write")
      login_as("writer")
      delete "/organizations/#{org.slug}/projects/#{project.slug}"
      expect(response).to have_http_status(:forbidden)
    end
  end
end
