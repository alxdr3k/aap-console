require "rails_helper"

RSpec.describe "MemberProjectPermissions", type: :request do
  let(:user_sub) { "admin-user" }
  let!(:org) { create(:organization) }
  let!(:admin_membership) { create(:org_membership, organization: org, user_sub: user_sub, role: "admin") }
  let!(:member_membership) { create(:org_membership, organization: org, user_sub: "target-user", role: "write") }
  let!(:project) { create(:project, :active, organization: org, slug: "app") }

  before { login_as(user_sub) }

  let(:json_headers) { { "ACCEPT" => "application/json" } }

  describe "POST /organizations/:org_slug/members/:user_sub/project_permissions" do
    it "grants a project permission and emits audit log" do
      expect {
        post "/organizations/#{org.slug}/members/target-user/project_permissions",
             params: { project_permission: { project_slug: "app", role: "read" } },
             headers: json_headers
      }.to change(ProjectPermission, :count).by(1)
        .and change { AuditLog.where(action: "member.project_permission.grant").count }.by(1)

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["role"]).to eq("read")
    end

    it "updates an existing permission (idempotent upsert)" do
      perm = create(:project_permission, org_membership: member_membership, project: project, role: "read")

      expect {
        post "/organizations/#{org.slug}/members/target-user/project_permissions",
             params: { project_permission: { project_slug: "app", role: "write" } },
             headers: json_headers
      }.not_to change(ProjectPermission, :count)

      expect(response).to have_http_status(:ok)
      expect(perm.reload.role).to eq("write")
    end

    it "returns 422 when target member is an org admin" do
      post "/organizations/#{org.slug}/members/#{user_sub}/project_permissions",
           params: { project_permission: { project_slug: "app", role: "read" } },
           headers: json_headers

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 404 for a missing project" do
      post "/organizations/#{org.slug}/members/target-user/project_permissions",
           params: { project_permission: { project_slug: "nonexistent", role: "read" } },
           headers: json_headers

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a missing membership" do
      post "/organizations/#{org.slug}/members/ghost-user/project_permissions",
           params: { project_permission: { project_slug: "app", role: "read" } },
           headers: json_headers

      expect(response).to have_http_status(:not_found)
    end

    it "returns 403 for non-admin member" do
      create(:org_membership, organization: org, user_sub: "reader", role: "read")
      login_as("reader")

      post "/organizations/#{org.slug}/members/target-user/project_permissions",
           params: { project_permission: { project_slug: "app", role: "read" } },
           headers: json_headers

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "PATCH /organizations/:org_slug/members/:user_sub/project_permissions/:project_slug" do
    let!(:permission) { create(:project_permission, org_membership: member_membership, project: project, role: "read") }

    it "updates the role and emits audit log" do
      expect {
        patch "/organizations/#{org.slug}/members/target-user/project_permissions/#{project.slug}",
              params: { project_permission: { role: "write" } },
              headers: json_headers
      }.to change { AuditLog.where(action: "member.project_permission.update").count }.by(1)

      expect(response).to have_http_status(:ok)
      expect(permission.reload.role).to eq("write")
    end

    it "returns 404 for missing permission" do
      other_project = create(:project, :active, organization: org, slug: "other")

      patch "/organizations/#{org.slug}/members/target-user/project_permissions/#{other_project.slug}",
            params: { project_permission: { role: "write" } },
            headers: json_headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /organizations/:org_slug/members/:user_sub/project_permissions/:project_slug" do
    let!(:permission) { create(:project_permission, org_membership: member_membership, project: project, role: "read") }

    it "revokes the permission and emits audit log" do
      expect {
        delete "/organizations/#{org.slug}/members/target-user/project_permissions/#{project.slug}",
               headers: json_headers
      }.to change(ProjectPermission, :count).by(-1)
        .and change { AuditLog.where(action: "member.project_permission.revoke").count }.by(1)

      expect(response).to have_http_status(:ok)
    end

    it "returns 403 for non-admin" do
      create(:org_membership, organization: org, user_sub: "reader", role: "read")
      login_as("reader")

      delete "/organizations/#{org.slug}/members/target-user/project_permissions/#{project.slug}",
             headers: json_headers

      expect(response).to have_http_status(:forbidden)
    end
  end
end
