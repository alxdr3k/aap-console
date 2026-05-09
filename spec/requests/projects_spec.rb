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

    it "creates an OAuth/PKCE project and redirects to provisioning" do
      post "/organizations/#{org.slug}/projects",
           params: { project: { name: "OAuth App", auth_type: "oauth", models: [ "azure-gpt4" ], s3_retention_days: 90 } },
           headers: wildcard_headers
      expect(response).to have_http_status(:see_other)
      project = Project.last
      expect(project.project_auth_config.auth_type).to eq("oauth")
    end

    it "rejects disallowed auth_type (saml is not enabled in UI yet)" do
      post "/organizations/#{org.slug}/projects",
           params: { project: { name: "P", auth_type: "saml", models: [ "azure-gpt4" ], s3_retention_days: 90 } },
           headers: wildcard_headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["errors"]).to include(match(/허용되지 않은 인증 방식/))
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

        # Default auth tab: project header and auth content
        get "/organizations/#{org.slug}/projects/#{project.slug}", headers: html_headers
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(project.name)
        expect(response.body).to include(project.app_id)
        expect(response.body).to include("aap-acme-project-oidc")
        expect(response.body).to include("완료 (경고)")
        expect(response.body).to include(organization_project_auth_config_path(org.slug, project.slug))

        # LiteLLM tab: model and edit link
        get "/organizations/#{org.slug}/projects/#{project.slug}?tab=litellm", headers: html_headers
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("azure-gpt4")
        expect(response.body).to include(organization_project_litellm_config_path(org.slug, project.slug))

        # History tab: config versions link
        get "/organizations/#{org.slug}/projects/#{project.slug}?tab=history", headers: html_headers
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(organization_project_config_versions_path(org.slug, project.slug))
      end

      it "defaults unknown tab param to auth tab" do
        create(:project_auth_config, project: project, auth_type: "oidc", keycloak_client_id: "aap-unknown-tab-test")
        get "/organizations/#{org.slug}/projects/#{project.slug}?tab=bogus", headers: html_headers
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("aap-unknown-tab-test")
        expect(response.body).not_to include("azure-gpt4")
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

    context "unified edit (auth + LiteLLM + metadata in one PATCH) — AC-024" do
      before do
        create(:project_auth_config,
               project: project,
               auth_type: "oidc",
               keycloak_client_id: "aap-#{org.slug}-#{project.slug}-oidc",
               keycloak_client_uuid: "server-owned-uuid")
      end

      it "creates a single Update provisioning job for combined dirty fields" do
        expect {
          patch "/organizations/#{org.slug}/projects/#{project.slug}",
                params: { project: {
                  name: "Renamed",
                  redirect_uris: [ "https://app.example.com/callback" ],
                  models: [ "azure-gpt4", "claude-sonnet" ],
                  s3_retention_days: 60
                } },
                headers: html_headers
        }.to change(ProvisioningJob, :count).by(1)

        job = project.provisioning_jobs.order(:id).last
        expect(job.operation).to eq("update")
        expect(job.input_snapshot).to include(
          "redirect_uris" => [ "https://app.example.com/callback" ],
          "models" => [ "azure-gpt4", "claude-sonnet" ],
          "s3_retention_days" => 60
        )
        expect(job.provisioning_steps.pluck(:name)).to match_array(%w[
          keycloak_client_update config_server_apply health_check
        ])
        expect(project.reload.name).to eq("Renamed")
        expect(project.status).to eq("update_pending")
        expect(response).to redirect_to(provisioning_job_path(job))
      end

      it "does not enqueue a provisioning job when only metadata is dirty" do
        expect {
          patch "/organizations/#{org.slug}/projects/#{project.slug}",
                params: { project: { name: "Only Meta", description: "x" } },
                headers: html_headers
        }.not_to change(ProvisioningJob, :count)

        expect(response).to redirect_to(organization_project_path(org.slug, project.slug))
        expect(project.reload.status).to eq("active")
      end

      it "rejects unified PATCH with external fields when an active job exists" do
        create(:provisioning_job, project: project, operation: "update", status: :in_progress)

        expect {
          patch "/organizations/#{org.slug}/projects/#{project.slug}",
                params: { project: { redirect_uris: [ "https://new.example.com/cb" ] } },
                headers: html_headers
        }.not_to change(project.provisioning_jobs.where(status: :pending), :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "coerces newline-separated redirect_uris textarea into an array" do
        expect {
          patch "/organizations/#{org.slug}/projects/#{project.slug}",
                params: { project: {
                  redirect_uris: "https://app.example.com/callback\nhttps://staging.example.com/callback\n"
                } },
                headers: html_headers
        }.to change(ProvisioningJob, :count).by(1)

        job = project.provisioning_jobs.order(:id).last
        expect(job.input_snapshot["redirect_uris"]).to eq(
          [ "https://app.example.com/callback", "https://staging.example.com/callback" ]
        )
      end

      it "does not enqueue a job when submitted external values match the persisted state" do
        project.project_auth_config.update!(redirect_uris: [ "https://app.example.com/callback" ])

        expect {
          patch "/organizations/#{org.slug}/projects/#{project.slug}",
                params: { project: {
                  redirect_uris: [ "https://app.example.com/callback" ]
                } },
                headers: html_headers
        }.not_to change(ProvisioningJob, :count)

        expect(response).to redirect_to(organization_project_path(org.slug, project.slug))
      end

      it "rejects unknown LiteLLM models with 422 even on the unified path" do
        expect {
          patch "/organizations/#{org.slug}/projects/#{project.slug}",
                params: { project: { models: [ "rogue-model" ] } },
                headers: html_headers
        }.not_to change(ProvisioningJob, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("허용되지 않은 모델")
      end

      it "rejects out-of-range S3 retention on the unified path" do
        expect {
          patch "/organizations/#{org.slug}/projects/#{project.slug}",
                params: { project: { s3_retention_days: 5000 } },
                headers: html_headers
        }.not_to change(ProvisioningJob, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("S3 Retention")
      end

      it "rejects insecure OAuth redirect URIs on the unified path" do
        project.project_auth_config.update!(auth_type: "oauth")

        expect {
          patch "/organizations/#{org.slug}/projects/#{project.slug}",
                params: { project: { redirect_uris: [ "http://evil.example.com/callback" ] } },
                headers: html_headers
        }.not_to change(ProvisioningJob, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("HTTPS")
      end
    end
  end

  describe "GET /organizations/:org_slug/projects/:slug/edit (unified edit form) — AC-024" do
    let!(:project) { create(:project, :active, organization: org) }

    before do
      create(:project_auth_config, project: project, auth_type: "oidc")
    end

    context "as project write+ member" do
      before do
        membership = create(:org_membership, organization: org, user_sub: user_sub, role: "write")
        create(:project_permission, org_membership: membership, project: project, role: "write")
      end

      it "renders the unified edit form with all sections" do
        get "/organizations/#{org.slug}/projects/#{project.slug}/edit", headers: html_headers

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Project 설정 편집")
        expect(response.body).to include("메타데이터")
        expect(response.body).to include("인증 설정")
        expect(response.body).to include("LiteLLM Config")
      end
    end

    it "returns 403 for read-only member" do
      read_membership = create(:org_membership, organization: org, user_sub: "reader", role: "read")
      create(:project_permission, org_membership: read_membership, project: project, role: "read")
      login_as("reader")

      get "/organizations/#{org.slug}/projects/#{project.slug}/edit", headers: html_headers
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
