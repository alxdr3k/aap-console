require "rails_helper"

RSpec.describe "ProvisioningJobs", type: :request do
  let(:user_sub) { "user-sub-123" }
  let!(:org) { create(:organization) }
  let!(:project) { create(:project, :active, organization: org) }
  let!(:provisioning_job) { create(:provisioning_job, project: project, operation: "create", status: :completed) }

  before { login_as(user_sub) }

  describe "GET /provisioning_jobs/:id" do
    context "as org admin" do
      before { create(:org_membership, organization: org, user_sub: user_sub, role: "admin") }

      it "returns 200" do
        get "/provisioning_jobs/#{provisioning_job.id}"
        expect(response).to have_http_status(:ok)
      end
    end

    context "as member with project permission" do
      before do
        membership = create(:org_membership, organization: org, user_sub: user_sub, role: "read")
        create(:project_permission, org_membership: membership, project: project, role: "read")
      end

      it "returns 200" do
        get "/provisioning_jobs/#{provisioning_job.id}"
        expect(response).to have_http_status(:ok)
      end
    end

    it "returns 403 for member without project permission" do
      create(:org_membership, organization: org, user_sub: user_sub, role: "read")
      get "/provisioning_jobs/#{provisioning_job.id}"
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /provisioning_jobs/:id/retry" do
    let!(:failed_job) { create(:provisioning_job, project: project, operation: "create", status: :failed) }

    before do
      membership = create(:org_membership, organization: org, user_sub: user_sub, role: "write")
      create(:project_permission, org_membership: membership, project: project, role: "write")
    end

    it "re-enqueues the job and returns 200" do
      post "/provisioning_jobs/#{failed_job.id}/retry"
      expect(response).to have_http_status(:ok)
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
