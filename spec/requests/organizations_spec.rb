require "rails_helper"

RSpec.describe "Organizations", type: :request do
  let(:user_sub) { "user-sub-123" }

  before { login_as(user_sub) }

  describe "GET /organizations" do
    let!(:org) { create(:organization) }
    let!(:other_org) { create(:organization) }

    before { create(:org_membership, organization: org, user_sub: user_sub) }

    it "returns 200 with accessible orgs" do
      get "/organizations"
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /organizations" do
    context "as super_admin" do
      before { login_as(user_sub, realm_roles: ["super_admin"]) }

      it "creates an org and redirects to it" do
        stub_langfuse_create_org(name: "Acme Corp")
        expect {
          post "/organizations", params: { organization: { name: "Acme Corp", description: "A team" } }
        }.to change(Organization, :count).by(1)
        expect(response).to redirect_to(organization_path(Organization.last.slug))
      end

      it "renders form on validation failure" do
        post "/organizations", params: { organization: { name: "A" } }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "as regular user" do
      it "returns 403" do
        post "/organizations", params: { organization: { name: "Acme" } }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "GET /organizations/:slug" do
    let!(:org) { create(:organization) }
    before { create(:org_membership, organization: org, user_sub: user_sub, role: "read") }

    it "returns 200" do
      get "/organizations/#{org.slug}"
      expect(response).to have_http_status(:ok)
    end

    it "returns 403 for non-member" do
      other_org = create(:organization)
      get "/organizations/#{other_org.slug}"
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "PATCH /organizations/:slug" do
    let!(:org) { create(:organization) }
    before { create(:org_membership, organization: org, user_sub: user_sub, role: "admin") }

    it "updates the org and redirects" do
      patch "/organizations/#{org.slug}", params: { organization: { name: "New Name" } }
      expect(org.reload.name).to eq("New Name")
      expect(response).to redirect_to(organization_path(org.slug))
    end

    it "returns 403 for non-admin" do
      other_org = create(:organization)
      create(:org_membership, organization: other_org, user_sub: user_sub, role: "read")
      patch "/organizations/#{other_org.slug}", params: { organization: { name: "New" } }
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "DELETE /organizations/:slug" do
    let!(:org) { create(:organization, langfuse_org_id: "lf-123") }

    context "as super_admin" do
      before do
        login_as(user_sub, realm_roles: ["super_admin"])
        stub_langfuse_delete_org(org_id: org.langfuse_org_id)
      end

      it "destroys the org and redirects" do
        expect {
          delete "/organizations/#{org.slug}"
        }.to change(Organization, :count).by(-1)
        expect(response).to redirect_to(organizations_path)
      end
    end

    context "as regular user" do
      it "returns 403" do
        delete "/organizations/#{org.slug}"
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
