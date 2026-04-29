require "rails_helper"

RSpec.describe "Members", type: :request do
  let(:user_sub) { "user-sub-123" }
  let!(:org) { create(:organization) }
  let(:json_headers) { { "ACCEPT" => "application/json" } }
  let(:html_headers) { { "ACCEPT" => "text/html" } }

  before { login_as(user_sub) }

  describe "GET /organizations/:org_slug/members" do
    before { create(:org_membership, organization: org, user_sub: user_sub, role: "read") }

    it "returns 200 with member list" do
      stub_keycloak_get_user(
        user_sub: user_sub,
        user: { id: user_sub, email: "reader@example.com", firstName: "Read", lastName: "User" }
      )

      get "/organizations/#{org.slug}/members", headers: json_headers

      expect(response).to have_http_status(:ok)
      member = JSON.parse(response.body).first
      expect(member.dig("user", "email")).to eq("reader@example.com")
    end

    it "renders the member management shell for HTML" do
      org.org_memberships.find_by!(user_sub: user_sub).update!(role: "admin")
      project = create(:project, :active, organization: org, name: "Chatbot")
      target = create(:org_membership, organization: org, user_sub: "pending-user", role: "read")
      create(:project_permission, org_membership: target, project: project, role: "read")
      stub_keycloak_get_user(
        user_sub: user_sub,
        user: { id: user_sub, email: "admin@example.com", firstName: "Admin", lastName: "User" }
      )
      stub_keycloak_get_user(user_sub: "pending-user", status: 404)

      get "/organizations/#{org.slug}/members", headers: html_headers

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/html")
      expect(response.body).to include("멤버 관리")
      expect(response.body).to include("멤버 추가")
      expect(response.body).to include("data-controller=\"role-permissions user-search\"")
      expect(response.body).to include("data-user-search-url-value=\"/users/search\"")
      expect(response.body).to include("input-&gt;user-search#clearSelection")
      expect(response.body).to include("admin@example.com")
      expect(response.body).to include("초대 대기 중")
      expect(response.body).to include("Project 권한")
      expect(response.body).to include("Chatbot")
    end

    it "renders the read-only member list without admin controls" do
      stub_keycloak_get_user(user_sub: user_sub)

      get "/organizations/#{org.slug}/members", headers: html_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("멤버 관리")
      expect(response.body).not_to include("멤버 추가")
      expect(response.body).not_to include("제거")
    end

    it "returns 403 for non-member" do
      other_org = create(:organization)
      get "/organizations/#{other_org.slug}/members", headers: json_headers
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /organizations/:org_slug/members" do
    before { create(:org_membership, organization: org, user_sub: user_sub, role: "admin") }

    it "creates a membership and returns 201" do
      stub_keycloak_get_user(user_sub: "new-user-sub")
      post "/organizations/#{org.slug}/members",
           params: { member: { user_sub: "new-user-sub", role: "read" } },
           headers: json_headers
      expect(response).to have_http_status(:created)
      expect(OrgMembership.exists?(organization: org, user_sub: "new-user-sub")).to be true
    end

    it "pre-assigns a member by creating a minimal Keycloak user from email" do
      stub_keycloak_create_user(email: "new@example.com", user_sub: "preassigned-user-sub")

      post "/organizations/#{org.slug}/members",
           params: { member: { email: "new@example.com", role: "read" } },
           headers: json_headers

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
           },
           headers: json_headers

      expect(response).to have_http_status(:created)
      membership = org.org_memberships.find_by(user_sub: "project-user-sub")
      permission = membership.project_permissions.find_by(project: project)
      expect(permission.role).to eq("write")
    end

    it "returns 422 when the selected Keycloak user no longer exists" do
      stub_keycloak_get_user(user_sub: "missing-user-sub", status: 404)

      post "/organizations/#{org.slug}/members",
           params: { member: { user_sub: "missing-user-sub", role: "read" } },
           headers: json_headers

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
           },
           headers: json_headers

      expect(response).to have_http_status(:not_found)
      expect(OrgMembership.exists?(organization: org, user_sub: "preassigned-user-sub")).to be false
      expect(WebMock).to have_requested(:delete, "#{KeycloakMock::BASE}/users/preassigned-user-sub")
    end

    it "returns 403 for non-admin member" do
      create(:org_membership, organization: org, user_sub: "other-user", role: "read")
      login_as("other-user")
      post "/organizations/#{org.slug}/members",
           params: { member: { user_sub: "another-user", role: "read" } },
           headers: json_headers
      expect(response).to have_http_status(:forbidden)
    end

    it "returns 422 for invalid params" do
      post "/organizations/#{org.slug}/members",
           params: { member: { user_sub: "", role: "read" } },
           headers: json_headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "creates a member from the HTML form and redirects" do
      stub_keycloak_create_user(email: "new@example.com", user_sub: "preassigned-user-sub")

      post "/organizations/#{org.slug}/members",
           params: { member: { email: "new@example.com", role: "read" } },
           headers: html_headers

      expect(response).to redirect_to(organization_members_path(org.slug))
      expect(org.org_memberships.find_by(user_sub: "preassigned-user-sub")).to be_present
    end
  end

  describe "PATCH /organizations/:org_slug/members/:user_sub" do
    let!(:target_membership) { create(:org_membership, organization: org, user_sub: "target-user", role: "read") }

    before { create(:org_membership, organization: org, user_sub: user_sub, role: "admin") }

    it "updates the role and returns 200" do
      patch "/organizations/#{org.slug}/members/target-user",
            params: { member: { role: "write" } },
            headers: json_headers
      expect(response).to have_http_status(:ok)
      expect(target_membership.reload.role).to eq("write")
    end

    it "returns 403 for non-admin" do
      other_org = create(:organization)
      create(:org_membership, organization: other_org, user_sub: user_sub, role: "read")
      patch "/organizations/#{other_org.slug}/members/target-user",
            params: { member: { role: "write" } },
            headers: json_headers
      expect(response).to have_http_status(:forbidden)
    end

    it "refuses to demote the last admin" do
      sole_admin_org = create(:organization)
      create(:org_membership, organization: sole_admin_org, user_sub: user_sub, role: "admin")
      patch "/organizations/#{sole_admin_org.slug}/members/#{user_sub}",
            params: { member: { role: "write" } },
            headers: json_headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to match(/last admin/i)
    end

    it "allows demotion when another admin exists" do
      create(:org_membership, organization: org, user_sub: "backup-admin", role: "admin")
      patch "/organizations/#{org.slug}/members/backup-admin",
            params: { member: { role: "write" } },
            headers: json_headers
      expect(response).to have_http_status(:ok)
    end

    it "clears explicit project permissions when a member becomes an admin" do
      project = create(:project, :active, organization: org, slug: "console")
      create(:project_permission, org_membership: target_membership, project: project, role: "write")

      patch "/organizations/#{org.slug}/members/target-user",
            params: { member: { role: "admin" } },
            headers: json_headers

      expect(response).to have_http_status(:ok)
      expect(target_membership.reload.role).to eq("admin")
      expect(target_membership.project_permissions).to be_empty
    end

    it "updates the role from the HTML form and redirects" do
      patch "/organizations/#{org.slug}/members/target-user",
            params: { member: { role: "write" } },
            headers: html_headers

      expect(response).to redirect_to(organization_members_path(org.slug))
      expect(target_membership.reload.role).to eq("write")
    end
  end

  describe "DELETE /organizations/:org_slug/members/:user_sub" do
    let!(:target_membership) { create(:org_membership, organization: org, user_sub: "target-user", role: "read") }

    before { create(:org_membership, organization: org, user_sub: user_sub, role: "admin") }

    it "destroys the membership and returns 200" do
      expect {
        delete "/organizations/#{org.slug}/members/target-user", headers: json_headers
      }.to change(OrgMembership, :count).by(-1)
      expect(response).to have_http_status(:ok)
    end

    it "returns 403 for non-admin" do
      other_org = create(:organization)
      create(:org_membership, organization: other_org, user_sub: user_sub, role: "read")
      delete "/organizations/#{other_org.slug}/members/target-user", headers: json_headers
      expect(response).to have_http_status(:forbidden)
    end

    it "refuses to remove the last admin (including self)" do
      sole_admin_org = create(:organization)
      create(:org_membership, organization: sole_admin_org, user_sub: user_sub, role: "admin")
      delete "/organizations/#{sole_admin_org.slug}/members/#{user_sub}", headers: json_headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to match(/last admin/i)
    end

    it "renders the members page error when HTML removes the last admin" do
      sole_admin_org = create(:organization)
      create(:org_membership, organization: sole_admin_org, user_sub: user_sub, role: "admin")

      delete "/organizations/#{sole_admin_org.slug}/members/#{user_sub}", headers: html_headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.media_type).to eq("text/html")
      expect(response.body).to include("Cannot remove the last admin")
      expect(response.body).to include("멤버 관리")
    end

    it "allows self-removal when another admin exists" do
      create(:org_membership, organization: org, user_sub: "backup-admin", role: "admin")
      expect {
        delete "/organizations/#{org.slug}/members/#{user_sub}", headers: json_headers
      }.to change(OrgMembership, :count).by(-1)
      expect(response).to have_http_status(:ok)
    end

    it "removes a member from the HTML form and redirects" do
      expect {
        delete "/organizations/#{org.slug}/members/target-user", headers: html_headers
      }.to change(OrgMembership, :count).by(-1)

      expect(response).to redirect_to(organization_members_path(org.slug))
    end

    it "redirects self-removal HTML to the organizations list" do
      create(:org_membership, organization: org, user_sub: "backup-admin", role: "admin")

      expect {
        delete "/organizations/#{org.slug}/members/#{user_sub}", headers: html_headers
      }.to change(OrgMembership, :count).by(-1)

      expect(response).to redirect_to(organizations_path)
    end
  end

  describe "Project permission management" do
    let!(:target_membership) { create(:org_membership, organization: org, user_sub: "target-user", role: "read") }
    let!(:project) { create(:project, :active, organization: org, slug: "console") }

    before { create(:org_membership, organization: org, user_sub: user_sub, role: "admin") }

    it "grants project permission and writes an audit log" do
      expect {
        post "/organizations/#{org.slug}/members/target-user/project_permissions",
             params: { project_permission: { project_slug: project.slug, role: "write" } },
             headers: json_headers
      }.to change(ProjectPermission, :count).by(1)
        .and change { AuditLog.where(action: "member.project_permission.grant").count }.by(1)

      expect(response).to have_http_status(:created)
      expect(target_membership.project_permissions.find_by(project: project)&.role).to eq("write")
    end

    it "updates project permission" do
      create(:project_permission, org_membership: target_membership, project: project, role: "read")

      patch "/organizations/#{org.slug}/members/target-user/project_permissions/#{project.slug}",
            params: { project_permission: { role: "write" } },
            headers: json_headers

      expect(response).to have_http_status(:ok)
      expect(target_membership.project_permissions.find_by(project: project)&.role).to eq("write")
    end

    it "revokes project permission" do
      create(:project_permission, org_membership: target_membership, project: project, role: "read")

      expect {
        delete "/organizations/#{org.slug}/members/target-user/project_permissions/#{project.slug}", headers: json_headers
      }.to change(ProjectPermission, :count).by(-1)

      expect(response).to have_http_status(:ok)
    end

    it "rejects explicit project permissions for admin members" do
      admin_member = create(:org_membership, organization: org, user_sub: "admin-target", role: "admin")

      post "/organizations/#{org.slug}/members/#{admin_member.user_sub}/project_permissions",
           params: { project_permission: { project_slug: project.slug, role: "write" } },
           headers: json_headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(admin_member.project_permissions).to be_empty
    end

    it "grants project permission from the HTML form and redirects" do
      post "/organizations/#{org.slug}/members/target-user/project_permissions",
           params: { project_permission: { project_slug: project.slug, role: "write" } },
           headers: html_headers

      expect(response).to redirect_to(organization_members_path(org.slug))
      expect(target_membership.project_permissions.find_by(project: project)&.role).to eq("write")
    end
  end
end
