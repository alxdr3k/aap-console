require "rails_helper"

RSpec.describe "Projects", type: :request do
  let(:user_sub) { "user-sub-123" }
  let!(:org) { create(:organization) }
  let(:wildcard_headers) { { "ACCEPT" => "*/*" } }
  let(:html_headers) { { "ACCEPT" => "text/html" } }

  before { login_as(user_sub) }

  describe "GET /organizations/:org_slug/projects" do
    let!(:project) { create(:project, :active, organization: org) }

    before { create(:org_membership, organization: org, user_sub: user_sub, role: "read") }

    it "returns 200 with accessible projects" do
      get "/organizations/#{org.slug}/projects"
      expect(response).to have_http_status(:ok)
    end

    it "preserves the JSON default for API-like project list requests" do
      membership = org.org_memberships.find_by!(user_sub: user_sub)
      create(:project_permission, org_membership: membership, project: project, role: "read")

      get "/organizations/#{org.slug}/projects", headers: wildcard_headers

      expect(response.media_type).to eq("application/json")
      expect(response.parsed_body.first["name"]).to eq(project.name)
    end

    it "renders the browser project list" do
      membership = org.org_memberships.find_by!(user_sub: user_sub)
      create(:project_permission, org_membership: membership, project: project, role: "read")

      get "/organizations/#{org.slug}/projects", headers: html_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(project.name)
      expect(response.body).to include(project.app_id)
    end

    it "returns 403 for non-member" do
      other_org = create(:organization)
      get "/organizations/#{other_org.slug}/projects"
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /organizations/:org_slug/projects/new" do
    before { create(:org_membership, organization: org, user_sub: user_sub, role: "admin") }

    it "renders the project creation form for admins" do
      get "/organizations/#{org.slug}/projects/new", headers: html_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("새 Project 생성")
      expect(response.body).to include("azure-gpt4")
      expect(response.body).to include("SAML")
      expect(response.body).to include("준비 중")
    end
  end

  describe "POST /organizations/:org_slug/projects" do
    before { create(:org_membership, organization: org, user_sub: user_sub, role: "admin") }

    it "creates a project and redirects to provisioning job" do
      post "/organizations/#{org.slug}/projects",
           params: { project: { name: "My Project", description: "desc", auth_type: "oidc", models: [ "azure-gpt4" ], s3_retention_days: 90 } },
           headers: wildcard_headers
      expect(response).to have_http_status(:see_other)
      project = Project.last
      expect(response).to redirect_to(provisioning_job_path(project.provisioning_jobs.last))
    end

    it "creates a project from the browser form and redirects to provisioning" do
      expect {
        post "/organizations/#{org.slug}/projects",
             params: {
               project: {
                 name: "UI Project",
                 description: "browser create",
                 auth_type: "oidc",
                 models: [ "azure-gpt4" ],
                 guardrails: [ "content-filter" ],
                 s3_retention_days: 90
               }
             },
             headers: html_headers
      }.to change(Project, :count).by(1)

      project = Project.last
      job = project.provisioning_jobs.last
      expect(response).to redirect_to(provisioning_job_path(job))
      expect(job.input_snapshot["models"]).to eq([ "azure-gpt4" ])
      expect(job.input_snapshot["guardrails"]).to eq([ "content-filter" ])
    end

    it "keeps projects named New reachable by skipping the reserved slug" do
      post "/organizations/#{org.slug}/projects",
           params: {
             project: {
               name: "New",
               auth_type: "oidc",
               models: [ "azure-gpt4" ],
               s3_retention_days: 90
             }
           },
           headers: html_headers

      project = Project.last
      expect(project.slug).to eq("new-2")

      get "/organizations/#{org.slug}/projects/#{project.slug}", headers: html_headers
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("New")
    end

    it "returns 422 on validation failure" do
      post "/organizations/#{org.slug}/projects",
           params: { project: { name: "A", auth_type: "oidc" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "renders browser validation errors without creating a project" do
      expect {
        post "/organizations/#{org.slug}/projects",
             params: { project: { name: "UI Project", auth_type: "oidc" } },
             headers: html_headers
      }.not_to change(Project, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("모델을 하나 이상 선택하세요.")
    end

    it "rejects unknown models for non-HTML requests" do
      post "/organizations/#{org.slug}/projects",
           params: { project: { name: "P", auth_type: "oidc", models: [ "gpt-5-unknown" ], s3_retention_days: 90 } },
           headers: wildcard_headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["errors"]).to include(match(/허용되지 않은 모델/))
    end

    it "rejects unknown guardrails for non-HTML requests" do
      post "/organizations/#{org.slug}/projects",
           params: { project: { name: "P", auth_type: "oidc", models: [ "azure-gpt4" ], guardrails: [ "evil-filter" ], s3_retention_days: 90 } },
           headers: wildcard_headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["errors"]).to include(match(/허용되지 않은 가드레일/))
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
        get "/organizations/#{org.slug}/projects/#{project.slug}", headers: wildcard_headers
        expect(response).to have_http_status(:ok)
      end

      it "preserves the JSON default for API-like project detail requests" do
        get "/organizations/#{org.slug}/projects/#{project.slug}", headers: wildcard_headers

        expect(response.media_type).to eq("application/json")
        expect(response.parsed_body["slug"]).to eq(project.slug)
      end

      it "renders the browser project detail page" do
        create(:project_auth_config, project: project, auth_type: "oidc", keycloak_client_id: "aap-acme-project-oidc")
        create(:provisioning_job, :completed_with_warnings, project: project, operation: "create")
        create(:config_version,
               project: project,
               change_summary: "Initial config",
               snapshot: { "models" => [ "azure-gpt4" ], "guardrails" => [ "content-filter" ], "s3_retention_days" => 90 })

        get "/organizations/#{org.slug}/projects/#{project.slug}", headers: html_headers

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(project.name)
        expect(response.body).to include(project.app_id)
        expect(response.body).to include("aap-acme-project-oidc")
        expect(response.body).to include("azure-gpt4")
        expect(response.body).to include("completed_with_warnings")
        expect(response.body).to include(organization_project_auth_config_path(org.slug, project.slug))
        expect(response.body).to include(organization_project_litellm_config_path(org.slug, project.slug))
        expect(response.body).to include(organization_project_config_versions_path(org.slug, project.slug))
      end

      it "renders an active provisioning warning and disables delete affordance" do
        active_job = create(:provisioning_job, :in_progress, project: project, operation: "update")

        get "/organizations/#{org.slug}/projects/#{project.slug}", headers: html_headers

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("진행 중인 프로비저닝 작업이 있습니다.")
        expect(response.body).to include(provisioning_job_path(active_job))
        expect(response.body).to include("Project 삭제 대기")
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
            params: { project: { name: "Updated Name" } },
            headers: wildcard_headers
      expect(response).to have_http_status(:ok)
      expect(project.reload.name).to eq("Updated Name")
    end

    it "updates browser metadata and redirects to the project detail" do
      patch "/organizations/#{org.slug}/projects/#{project.slug}",
            params: { project: { name: "Browser Updated", description: "Edited" } },
            headers: html_headers

      expect(response).to redirect_to(organization_project_path(org.slug, project.slug))
      expect(project.reload.name).to eq("Browser Updated")
      expect(project.description).to eq("Edited")
    end

    it "renders browser validation errors" do
      patch "/organizations/#{org.slug}/projects/#{project.slug}",
            params: { project: { name: "A" } },
            headers: html_headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Validation failed")
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

    it "starts delete provisioning from the browser and redirects to the job" do
      delete "/organizations/#{org.slug}/projects/#{project.slug}", headers: html_headers

      job = project.reload.provisioning_jobs.where(operation: "delete").last
      expect(response).to redirect_to(provisioning_job_path(job))
      expect(project.status).to eq("deleting")
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
