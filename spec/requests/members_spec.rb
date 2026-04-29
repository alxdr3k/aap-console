require "rails_helper"

RSpec.describe "Members", type: :request do
  let(:user_sub) { "user-sub-123" }
  let!(:org) { create(:organization) }

  before { login_as(user_sub) }

  describe "GET /organizations/:org_slug/members" do
    before { create(:org_membership, organization: org, user_sub: user_sub, role: "read") }

    it "returns 200 with member list" do
      stub_keycloak_get_user(
        user_sub: user_sub,
        user: { id: user_sub, email: "reader@example.com", firstName: "Read", lastName: "User" }
      )

      get "/organizations/#{org.slug}/members"

      expect(response).to have_http_status(:ok)
      member = JSON.parse(response.body).first
      expect(member.dig("user", "email")).to eq("reader@example.com")
    end

    it "returns 403 for non-member" do
      other_org = create(:organization)
      get "/organizations/#{other_org.slug}/members"
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /organizations/:org_slug/members" do
    before { create(:org_membership, organization: org, user_sub: user_sub, role: "admin") }

    it "creates a membership and returns 201" do
      stub_keycloak_get_user(user_sub: "new-user-sub")
      post "/organizations/#{org.slug}/members",
           params: { member: { user_sub: "new-user-sub", role: "read" } }
      expect(response).to have_http_status(:created)
      expect(OrgMembership.exists?(organization: org, user_sub: "new-user-sub")).to be true
    end

    it "pre-assigns a member by creating a minimal Keycloak user from email" do
      stub_keycloak_create_user(email: "new@example.com", user_sub: "preassigned-user-sub")

      post "/organizations/#{org.slug}/members",
           params: { member: { email: "new@example.com", role: "read" } }

      expect(response).to have_http_status(:created)
      membership = org.org_memberships.find_by(user_sub: "preassigned-user-sub")
      expect(membership).to be_present
      expect(membership.joined_at).to be_nil
    end

    it "creates project permissions with a new write/read membership" do
      project = create(:project, :active, organization: org, slug: "console")
      stub_keycloak_get_user(user_sub: "project-user-sub")

      post "/organizations/#{org.slug}/members",
           params: {
             member: {
               user_sub: "project-user-sub",
               role: "write",
               project_permissions: [ { project_slug: project.slug, role: "write" } ]
             }
           }

      expect(response).to have_http_status(:created)
      membership = org.org_memberships.find_by(user_sub: "project-user-sub")
      permission = membership.project_permissions.find_by(project: project)
      expect(permission.role).to eq("write")
    end

    it "returns 422 when the selected Keycloak user no longer exists" do
      stub_keycloak_get_user(user_sub: "missing-user-sub", status: 404)

      post "/organizations/#{org.slug}/members",
           params: { member: { user_sub: "missing-user-sub", role: "read" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(OrgMembership.exists?(organization: org, user_sub: "missing-user-sub")).to be false
    end

    it "compensates a pre-created Keycloak user when local project permission validation fails" do
      stub_keycloak_create_user(email: "new@example.com", user_sub: "preassigned-user-sub")
      stub_keycloak_delete_user(user_sub: "preassigned-user-sub")

      post "/organizations/#{org.slug}/members",
           params: {
             member: {
               email: "new@example.com",
               role: "write",
               project_permissions: [ { project_slug: "missing-project", role: "write" } ]
             }
           }

      expect(response).to have_http_status(:not_found)
      expect(OrgMembership.exists?(organization: org, user_sub: "preassigned-user-sub")).to be false
      expect(WebMock).to have_requested(:delete, "#{KeycloakMock::BASE}/users/preassigned-user-sub")
    end

    it "returns 403 for non-admin member" do
      create(:org_membership, organization: org, user_sub: "other-user", role: "read")
      login_as("other-user")
      post "/organizations/#{org.slug}/members",
           params: { member: { user_sub: "another-user", role: "read" } }
      expect(response).to have_http_status(:forbidden)
    end

    it "returns 422 for invalid params" do
      post "/organizations/#{org.slug}/members",
           params: { member: { user_sub: "", role: "read" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /organizations/:org_slug/members/:user_sub" do
    let!(:target_membership) { create(:org_membership, organization: org, user_sub: "target-user", role: "read") }

    before { create(:org_membership, organization: org, user_sub: user_sub, role: "admin") }

    it "updates the role and returns 200" do
      patch "/organizations/#{org.slug}/members/target-user",
            params: { member: { role: "write" } }
      expect(response).to have_http_status(:ok)
      expect(target_membership.reload.role).to eq("write")
    end

    it "returns 403 for non-admin" do
      other_org = create(:organization)
      create(:org_membership, organization: other_org, user_sub: user_sub, role: "read")
      patch "/organizations/#{other_org.slug}/members/target-user",
            params: { member: { role: "write" } }
      expect(response).to have_http_status(:forbidden)
    end

    it "refuses to demote the last admin" do
      sole_admin_org = create(:organization)
      create(:org_membership, organization: sole_admin_org, user_sub: user_sub, role: "admin")
      patch "/organizations/#{sole_admin_org.slug}/members/#{user_sub}",
            params: { member: { role: "write" } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to match(/last admin/i)
    end

    it "allows demotion when another admin exists" do
      create(:org_membership, organization: org, user_sub: "backup-admin", role: "admin")
      patch "/organizations/#{org.slug}/members/backup-admin",
            params: { member: { role: "write" } }
      expect(response).to have_http_status(:ok)
    end

    it "clears explicit project permissions when a member becomes an admin" do
      project = create(:project, :active, organization: org, slug: "console")
      create(:project_permission, org_membership: target_membership, project: project, role: "write")

      patch "/organizations/#{org.slug}/members/target-user",
            params: { member: { role: "admin" } }

      expect(response).to have_http_status(:ok)
      expect(target_membership.reload.role).to eq("admin")
      expect(target_membership.project_permissions).to be_empty
    end
  end

  describe "DELETE /organizations/:org_slug/members/:user_sub" do
    let!(:target_membership) { create(:org_membership, organization: org, user_sub: "target-user", role: "read") }

    before { create(:org_membership, organization: org, user_sub: user_sub, role: "admin") }

    it "destroys the membership and returns 200" do
      expect {
        delete "/organizations/#{org.slug}/members/target-user"
      }.to change(OrgMembership, :count).by(-1)
      expect(response).to have_http_status(:ok)
    end

    it "returns 403 for non-admin" do
      other_org = create(:organization)
      create(:org_membership, organization: other_org, user_sub: user_sub, role: "read")
      delete "/organizations/#{other_org.slug}/members/target-user"
      expect(response).to have_http_status(:forbidden)
    end

    it "refuses to remove the last admin (including self)" do
      sole_admin_org = create(:organization)
      create(:org_membership, organization: sole_admin_org, user_sub: user_sub, role: "admin")
      delete "/organizations/#{sole_admin_org.slug}/members/#{user_sub}"
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to match(/last admin/i)
    end

    it "allows self-removal when another admin exists" do
      create(:org_membership, organization: org, user_sub: "backup-admin", role: "admin")
      expect {
        delete "/organizations/#{org.slug}/members/#{user_sub}"
      }.to change(OrgMembership, :count).by(-1)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "Project permission management" do
    let!(:target_membership) { create(:org_membership, organization: org, user_sub: "target-user", role: "read") }
    let!(:project) { create(:project, :active, organization: org, slug: "console") }

    before { create(:org_membership, organization: org, user_sub: user_sub, role: "admin") }

    it "grants project permission and writes an audit log" do
      expect {
        post "/organizations/#{org.slug}/members/target-user/project_permissions",
             params: { project_permission: { project_slug: project.slug, role: "write" } }
      }.to change(ProjectPermission, :count).by(1)
        .and change { AuditLog.where(action: "member.project_permission.grant").count }.by(1)

      expect(response).to have_http_status(:created)
      expect(target_membership.project_permissions.find_by(project: project)&.role).to eq("write")
    end

    it "updates project permission" do
      create(:project_permission, org_membership: target_membership, project: project, role: "read")

      patch "/organizations/#{org.slug}/members/target-user/project_permissions/#{project.slug}",
            params: { project_permission: { role: "write" } }

      expect(response).to have_http_status(:ok)
      expect(target_membership.project_permissions.find_by(project: project)&.role).to eq("write")
    end

    it "revokes project permission" do
      create(:project_permission, org_membership: target_membership, project: project, role: "read")

      expect {
        delete "/organizations/#{org.slug}/members/target-user/project_permissions/#{project.slug}"
      }.to change(ProjectPermission, :count).by(-1)

      expect(response).to have_http_status(:ok)
    end

    it "rejects explicit project permissions for admin members" do
      admin_member = create(:org_membership, organization: org, user_sub: "admin-target", role: "admin")

      post "/organizations/#{org.slug}/members/#{admin_member.user_sub}/project_permissions",
           params: { project_permission: { project_slug: project.slug, role: "write" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(admin_member.project_permissions).to be_empty
    end
  end
end
