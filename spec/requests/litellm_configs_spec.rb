require "rails_helper"

RSpec.describe "LitellmConfigs", type: :request do
  let(:user_sub) { "user-sub-123" }
  let!(:org) { create(:organization) }
  let!(:project) { create(:project, :active, organization: org) }
  let(:html_headers) { { "ACCEPT" => "text/html" } }
  let(:json_headers) { { "ACCEPT" => "application/json" } }
  let(:wildcard_headers) { { "ACCEPT" => "*/*" } }

  before { login_as(user_sub) }

  describe "GET /organizations/:org_slug/projects/:slug/litellm_config" do
    before do
      membership = create(:org_membership, organization: org, user_sub: user_sub, role: "read")
      create(:project_permission, org_membership: membership, project: project, role: "read")
    end

    it "returns 200" do
      get "/organizations/#{org.slug}/projects/#{project.slug}/litellm_config"
      expect(response).to have_http_status(:ok)
    end

    it "returns the latest config_version snapshot at the response root" do
      create(:config_version,
             project: project,
             version_id: "v-1",
             snapshot: { "models" => [ "azure-gpt4" ], "s3_retention_days" => 90,
                         "s3_path" => "#{org.slug}/#{project.slug}/", "app_id" => project.app_id })
      get "/organizations/#{org.slug}/projects/#{project.slug}/litellm_config", headers: wildcard_headers
      body = JSON.parse(response.body)
      expect(body["models"]).to eq([ "azure-gpt4" ])
      expect(body["s3_retention_days"]).to eq(90)
    end

    it "returns 403 for member without project permission" do
      other_project = create(:project, :active, organization: org)
      get "/organizations/#{org.slug}/projects/#{other_project.slug}/litellm_config"
      expect(response).to have_http_status(:forbidden)
    end

    it "renders the browser page for project readers" do
      create(:config_version,
             project: project,
             version_id: "v-2",
             snapshot: { "models" => [ "azure-gpt4" ], "guardrails" => [ "content-filter" ],
                         "s3_retention_days" => 90, "s3_path" => "#{org.slug}/#{project.slug}/" })

      get "/organizations/#{org.slug}/projects/#{project.slug}/litellm_config", headers: html_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("LiteLLM Config")
      expect(response.body).to include("azure-gpt4")
      expect(response.body).to include("content-filter")
      expect(response.body).to include("read only")
    end
  end

  describe "PATCH /organizations/:org_slug/projects/:slug/litellm_config" do
    before do
      membership = create(:org_membership, organization: org, user_sub: user_sub, role: "write")
      create(:project_permission, org_membership: membership, project: project, role: "write")
    end

    it "enqueues update provisioning and returns 202 with provisioning_job_id" do
      patch "/organizations/#{org.slug}/projects/#{project.slug}/litellm_config",
            params: { litellm_config: { models: [ "azure-gpt4" ], s3_retention_days: 90 } },
            headers: wildcard_headers
      expect(response).to have_http_status(:accepted)
      job = project.provisioning_jobs.where(operation: "update").last
      expect(job).to be_present
      body = JSON.parse(response.body)
      expect(body["provisioning_job_id"]).to eq(job.id)
    end

    it "keeps explicit JSON clients on the JSON contract" do
      patch "/organizations/#{org.slug}/projects/#{project.slug}/litellm_config",
            params: { litellm_config: { models: [ "azure-gpt4" ], s3_retention_days: 90 } },
            headers: json_headers

      expect(response).to have_http_status(:accepted)
      expect(response.media_type).to eq("application/json")
      expect(response.parsed_body["provisioning_job_id"]).to eq(project.provisioning_jobs.where(operation: "update").last.id)
    end

    it "redirects browser updates to the provisioning job detail page" do
      patch "/organizations/#{org.slug}/projects/#{project.slug}/litellm_config",
            params: { litellm_config: { models: [ "azure-gpt4" ], s3_retention_days: 90 } },
            headers: html_headers

      expect(response).to redirect_to(provisioning_job_path(project.provisioning_jobs.where(operation: "update").last))
    end

    it "renders browser validation errors when no models are selected" do
      patch "/organizations/#{org.slug}/projects/#{project.slug}/litellm_config",
            params: { litellm_config: { models: [ "" ], s3_retention_days: 90 } },
            headers: html_headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("모델을 하나 이상 선택하세요.")
    end

    it "returns 403 for read-only member" do
      other_project = create(:project, :active, organization: org)
      read_membership = create(:org_membership, organization: org, user_sub: "reader", role: "read")
      create(:project_permission, org_membership: read_membership, project: other_project, role: "read")
      login_as("reader")
      patch "/organizations/#{org.slug}/projects/#{other_project.slug}/litellm_config",
            params: { litellm_config: { models: [ "azure-gpt4" ] } }
      expect(response).to have_http_status(:forbidden)
    end
  end
end
