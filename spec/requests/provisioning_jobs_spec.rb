require "rails_helper"

RSpec.describe "ProvisioningJobs", type: :request do
  let(:user_sub) { "user-sub-123" }
  let!(:org) { create(:organization) }
  let!(:project) { create(:project, :active, organization: org) }
  let!(:provisioning_job) { create(:provisioning_job, project: project, operation: "create", status: :completed) }
  let(:wildcard_headers) { { "ACCEPT" => "*/*" } }
  let(:html_headers) { { "ACCEPT" => "text/html" } }

  before { login_as(user_sub) }

  describe "GET /provisioning_jobs/:id" do
    context "as org admin" do
      before { create(:org_membership, organization: org, user_sub: user_sub, role: "admin") }

      it "returns 200" do
        get "/provisioning_jobs/#{provisioning_job.id}", headers: wildcard_headers
        expect(response).to have_http_status(:ok)
      end

      it "preserves the JSON default for API-like provisioning job requests" do
        create(:provisioning_step, :app_registry_register, :completed, provisioning_job: provisioning_job)
        create(:provisioning_step, :health_check, :completed, provisioning_job: provisioning_job)

        get "/provisioning_jobs/#{provisioning_job.id}", headers: wildcard_headers

        expect(response.media_type).to eq("application/json")
        expect(response.parsed_body["status"]).to eq("completed")
        expect(response.parsed_body["steps"].map { |step| step["name"] }).to eq(%w[app_registry_register health_check])
      end

      it "renders the browser timeline from persisted job and step state" do
        provisioning_job.update!(
          status: :completed_with_warnings,
          started_at: 2.minutes.ago,
          completed_at: 1.minute.ago,
          warnings: [ "Health check warning" ]
        )
        create(:provisioning_step, :app_registry_register, :completed, provisioning_job: provisioning_job)
        create(:provisioning_step, :langfuse_project_create, :failed,
               provisioning_job: provisioning_job,
               retry_count: 3,
               error_message: "Connection refused")

        get "/provisioning_jobs/#{provisioning_job.id}", headers: html_headers

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Project 생성 프로비저닝")
        expect(response.body).to include(project.name)
        expect(response.body).to include("completed_with_warnings")
        expect(response.body).to include("App Registry Register")
        expect(response.body).to include("Langfuse Project Create")
        expect(response.body).to include("Connection refused")
        expect(response.body).to include("Health check warning")
      end

      it "renders the not found shell for HTML" do
        get "/provisioning_jobs/999999", headers: html_headers

        expect(response).to have_http_status(:not_found)
        expect(response.body).to include("프로비저닝 Job을 찾을 수 없습니다.")
      end

      it "renders an individual step partial for browser replacement" do
        step = create(:provisioning_step, :app_registry_register, :completed, provisioning_job: provisioning_job)

        get "/provisioning_jobs/#{provisioning_job.id}/steps/#{step.id}", headers: html_headers

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(%(data-step-id="#{step.id}"))
        expect(response.body).to include("App Registry Register")
        expect(response.body).not_to include("<html")
      end

      it "returns individual step JSON for API-like replacement requests" do
        step = create(:provisioning_step, :app_registry_register, :completed, provisioning_job: provisioning_job)

        get "/provisioning_jobs/#{provisioning_job.id}/steps/#{step.id}", headers: wildcard_headers

        expect(response.media_type).to eq("application/json")
        expect(response.parsed_body["name"]).to eq("app_registry_register")
      end

      it "renders manual-intervention retry controls for retryable jobs" do
        failed_job = create(:provisioning_job, :rollback_failed, project: project, operation: "delete")

        get "/provisioning_jobs/#{failed_job.id}", headers: html_headers

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("수동 조치 필요")
        expect(response.body).to include("수동 재시도")
        expect(response.body).to include(retry_provisioning_job_path(failed_job))
      end
    end

    context "as member with project permission" do
      before do
        membership = create(:org_membership, organization: org, user_sub: user_sub, role: "read")
        create(:project_permission, org_membership: membership, project: project, role: "read")
      end

      it "returns 200" do
        get "/provisioning_jobs/#{provisioning_job.id}", headers: html_headers
        expect(response).to have_http_status(:ok)
      end
    end

    it "returns 403 for member without project permission" do
      create(:org_membership, organization: org, user_sub: user_sub, role: "read")
      get "/provisioning_jobs/#{provisioning_job.id}", headers: html_headers
      expect(response).to have_http_status(:forbidden)
    end

    it "returns 403 for step partials without project permission" do
      step = create(:provisioning_step, :app_registry_register, :completed, provisioning_job: provisioning_job)
      create(:org_membership, organization: org, user_sub: user_sub, role: "read")

      get "/provisioning_jobs/#{provisioning_job.id}/steps/#{step.id}", headers: html_headers

      expect(response).to have_http_status(:forbidden)
    end

    it "does not expose step existence before project permission" do
      create(:org_membership, organization: org, user_sub: user_sub, role: "read")

      get "/provisioning_jobs/#{provisioning_job.id}/steps/999999", headers: html_headers

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /provisioning_jobs/:id/retry" do
    let!(:failed_job) { create(:provisioning_job, project: project, operation: "create", status: :failed) }

    before do
      membership = create(:org_membership, organization: org, user_sub: user_sub, role: "write")
      create(:project_permission, org_membership: membership, project: project, role: "write")
    end

    it "re-enqueues the job, marks it retrying, and returns 200" do
      post "/provisioning_jobs/#{failed_job.id}/retry", headers: wildcard_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["status"]).to eq("retrying")
      expect(failed_job.reload).to be_retrying
    end

    it "retries from the browser and restores the project provisioning state" do
      failed_job.project.update!(status: :provision_failed)

      post "/provisioning_jobs/#{failed_job.id}/retry", headers: html_headers

      expect(response).to redirect_to(provisioning_job_path(failed_job))
      expect(failed_job.reload).to be_retrying
      expect(failed_job.project.reload).to be_provisioning
    end

    it "rejects retry when another provisioning job is already active" do
      create(:provisioning_job, :in_progress, project: project, operation: "update")

      post "/provisioning_jobs/#{failed_job.id}/retry", headers: wildcard_headers

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body["error"]).to eq("Another provisioning job is in progress")
      expect(failed_job.reload).to be_failed
    end

    it "returns 403 for read-only member" do
      other_project = create(:project, :active, organization: org)
      failed_job2 = create(:provisioning_job, project: other_project, operation: "create", status: :failed)
      read_membership = create(:org_membership, organization: org, user_sub: "reader", role: "read")
      create(:project_permission, org_membership: read_membership, project: other_project, role: "read")
      login_as("reader")
      post "/provisioning_jobs/#{failed_job2.id}/retry"
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /provisioning_jobs/:id/secrets" do
    before do
      membership = create(:org_membership, organization: org, user_sub: user_sub, role: "write")
      create(:project_permission, org_membership: membership, project: project, role: "write")
    end

    it "returns 200 (empty when no cached secrets)" do
      get "/provisioning_jobs/#{provisioning_job.id}/secrets"
      expect(response).to have_http_status(:ok)
    end

    it "returns 403 for read-only member" do
      other_project = create(:project, :active, organization: org)
      job2 = create(:provisioning_job, project: other_project, operation: "create", status: :completed)
      read_membership = create(:org_membership, organization: org, user_sub: "reader", role: "read")
      create(:project_permission, org_membership: read_membership, project: other_project, role: "read")
      login_as("reader")
      get "/provisioning_jobs/#{job2.id}/secrets"
      expect(response).to have_http_status(:forbidden)
    end
  end
end
