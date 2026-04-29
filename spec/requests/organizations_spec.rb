require "rails_helper"

RSpec.describe "Organizations", type: :request do
  let(:user_sub) { "user-sub-123" }

  before { login_as(user_sub) }

  describe "GET /organizations" do
    let!(:org) { create(:organization) }
    let!(:other_org) { create(:organization) }

    before { create(:org_membership, organization: org, user_sub: user_sub, role: "admin") }

    it "returns 200 with accessible orgs" do
      get "/organizations"
      expect(response).to have_http_status(:ok)
    end

    it "renders the authenticated application shell for HTML" do
      create(:project, :active, organization: org)

      get "/organizations"

      expect(response.body).to include("AAP Console")
      expect(response.body).to include("Organizations")
      expect(response.body).to include(org.name)
      expect(response.body).to include("1 Project")
      expect(response.body).to include("admin")
      expect(response.body).not_to include("새 Organization 생성")
      expect(response.media_type).to eq("text/html")
    end

    it "keeps JSON response compatibility" do
      get "/organizations", headers: { "ACCEPT" => "application/json" }

      payload = response.parsed_body
      expect(payload.pluck("slug")).to contain_exactly(org.slug)
    end

    context "with no memberships" do
      before do
        OrgMembership.delete_all
      end

      it "renders a non-admin empty state without a create CTA" do
        get "/organizations"

        expect(response.body).to include("소속된 Organization이 없습니다.")
        expect(response.body).to include("관리자에게 권한을 요청하세요.")
        expect(response.body).not_to include("새 Organization 생성")
      end
    end

    context "as super_admin" do
      before do
        login_as(user_sub, realm_roles: [ "super_admin" ])
      end

      it "renders all organizations with the create affordance" do
        get "/organizations"

        expect(response.body).to include(org.name)
        expect(response.body).to include(other_org.name)
        expect(response.body).to include("새 Organization")
      end

      it "renders the super_admin empty state with a create CTA" do
        Project.delete_all
        OrgMembership.delete_all
        Organization.delete_all

        get "/organizations"

        expect(response.body).to include("Organization이 없습니다.")
        expect(response.body).to include("새 Organization 생성")
      end
    end
  end

  describe "GET /organizations/new" do
    it "returns 403 for regular users" do
      get "/organizations/new"

      expect(response).to have_http_status(:forbidden)
    end

    it "renders the new form for super_admin" do
      login_as(user_sub, realm_roles: [ "super_admin" ])

      get "/organizations/new"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("새 Organization 생성")
      expect(response.body).to include("초기 관리자 user_sub")
    end
  end

  describe "POST /organizations" do
    context "as super_admin" do
      before { login_as(user_sub, realm_roles: [ "super_admin" ]) }

      it "creates an org and redirects to it" do
        stub_langfuse_create_org(name: "Acme Corp")
        expect {
          post "/organizations", params: { organization: { name: "Acme Corp", description: "A team" } }
        }.to change(Organization, :count).by(1)
        expect(response).to redirect_to(organization_path(Organization.last.slug))
      end

      it "assigns a designated initial admin when provided" do
        stub_langfuse_create_org(name: "Acme Corp")

        post "/organizations",
             params: { organization: { name: "Acme Corp", initial_admin_user_sub: "selected-admin-sub" } }

        org = Organization.last
        membership = org.org_memberships.find_by(user_sub: "selected-admin-sub")
        expect(membership.role).to eq("admin")
        expect(membership.joined_at).to be_nil
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

    it "keeps JSON as the wildcard Accept default" do
      get "/organizations/#{org.slug}", headers: { "ACCEPT" => "*/*" }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      expect(response.parsed_body.fetch("slug")).to eq(org.slug)
    end

    it "keeps JSON response compatibility" do
      get "/organizations/#{org.slug}", headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch("slug")).to eq(org.slug)
    end

    it "renders the organization detail shell for HTML" do
      create(:project, :active, organization: org, name: "Chatbot")

      get "/organizations/#{org.slug}", headers: { "ACCEPT" => "text/html" }

      expect(response.media_type).to eq("text/html")
      expect(response.body).to include(org.name)
      expect(response.body).to include("Projects")
      expect(response.body).to include("멤버 요약")
      expect(response.body).to include("접근 가능한 Project가 없습니다.")
    end

    it "renders the edit affordance for org admins" do
      org.org_memberships.find_by!(user_sub: user_sub).update!(role: "admin")

      get "/organizations/#{org.slug}", headers: { "ACCEPT" => "text/html" }

      expect(response.body).to include("편집")
      expect(response.body).to include(edit_organization_path(org.slug))
    end

    it "returns 403 for non-member" do
      other_org = create(:organization)
      get "/organizations/#{other_org.slug}"
      expect(response).to have_http_status(:forbidden)
    end

    it "keeps JSON 404 for wildcard Accept" do
      get "/organizations/missing", headers: { "ACCEPT" => "*/*" }

      expect(response).to have_http_status(:not_found)
      expect(response.media_type).to eq("application/json")
      expect(response.parsed_body).to eq("error" => "Not found")
    end

    it "renders the not found shell for HTML" do
      get "/organizations/missing", headers: { "ACCEPT" => "text/html" }

      expect(response).to have_http_status(:not_found)
      expect(response.media_type).to eq("text/html")
      expect(response.body).to include("AAP Console")
      expect(response.body).to include("Organization을 찾을 수 없습니다.")
    end
  end

  describe "GET /organizations/:slug/edit" do
    let!(:org) { create(:organization, name: "Acme Corp", description: "AI services") }

    it "renders the edit form for org admins" do
      create(:org_membership, organization: org, user_sub: user_sub, role: "admin")

      get "/organizations/#{org.slug}/edit", headers: { "ACCEPT" => "text/html" }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/html")
      expect(response.body).to include("Organization 편집")
      expect(response.body).to include("Acme Corp")
      expect(response.body).not_to include("초기 관리자 user_sub")
    end

    it "returns 403 for read-only members" do
      create(:org_membership, organization: org, user_sub: user_sub, role: "read")

      get "/organizations/#{org.slug}/edit", headers: { "ACCEPT" => "text/html" }

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "PATCH /organizations/:slug" do
    let!(:org) { create(:organization, langfuse_org_id: "lf-123") }
    before { create(:org_membership, organization: org, user_sub: user_sub, role: "admin") }

    it "updates the org and redirects" do
      stub_langfuse_update_org(org_id: org.langfuse_org_id, name: "New Name")

      patch "/organizations/#{org.slug}", params: { organization: { name: "New Name" } }
      expect(org.reload.name).to eq("New Name")
      expect(response).to redirect_to(organization_path(org.slug))
    end

    it "renders the edit form on validation failure for HTML" do
      patch "/organizations/#{org.slug}",
            params: { organization: { name: "A" } },
            headers: { "ACCEPT" => "text/html" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.media_type).to eq("text/html")
      expect(response.body).to include("Organization 편집")
      expect(response.body).to include("Name is too short")
    end

    it "keeps JSON response compatibility on validation failure" do
      patch "/organizations/#{org.slug}",
            params: { organization: { name: "A" } },
            headers: { "ACCEPT" => "application/json" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.fetch("errors").first).to include("Name is too short")
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
        login_as(user_sub, realm_roles: [ "super_admin" ])
        stub_langfuse_delete_org(org_id: org.langfuse_org_id)
      end

      it "destroys the org and redirects" do
        expect {
          delete "/organizations/#{org.slug}"
        }.to change(Organization, :count).by(-1)
        expect(response).to redirect_to(organizations_path)
      end

      it "renders the show shell with an error when deletion fails for HTML" do
        project = create(:project, :update_pending, organization: org)
        create(:provisioning_job, :in_progress, project: project, operation: "update")

        expect {
          delete "/organizations/#{org.slug}"
        }.not_to change(Organization, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.media_type).to eq("text/html")
        expect(response.body).to include("Another provisioning job is in progress")
        expect(response.body).to include(org.name)
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
