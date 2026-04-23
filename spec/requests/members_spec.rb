require "rails_helper"

RSpec.describe "Members", type: :request do
  let(:user_sub) { "user-sub-123" }
  let!(:org) { create(:organization) }

  before { login_as(user_sub) }

  describe "GET /organizations/:org_slug/members" do
    before { create(:org_membership, organization: org, user_sub: user_sub, role: "read") }

    it "returns 200 with member list" do
      get "/organizations/#{org.slug}/members"
      expect(response).to have_http_status(:ok)
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
end
