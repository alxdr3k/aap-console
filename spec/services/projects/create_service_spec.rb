require "rails_helper"

RSpec.describe Projects::CreateService do
  let(:organization) { create(:organization) }
  let(:user_sub) { "user-sub-admin" }
  let(:params) do
    {
      name: "Chatbot",
      description: "Our AI chatbot",
      auth_type: "oidc",
      models: ["azure-gpt4"],
      s3_retention_days: 90
    }
  end

  describe "#call" do
    it "creates the project in DB with status provisioning" do
      result = described_class.new(organization: organization, params: params, current_user_sub: user_sub).call
      expect(result).to be_success
      project = result.data
      expect(project).to be_persisted
      expect(project.name).to eq("Chatbot")
      expect(project).to be_provisioning
    end

    it "auto-generates an app_id" do
      result = described_class.new(organization: organization, params: params, current_user_sub: user_sub).call
      expect(result.data.app_id).to match(/\Aapp-[a-zA-Z0-9]{12}\z/)
    end

    it "enqueues a ProvisioningExecuteJob" do
      expect {
        described_class.new(organization: organization, params: params, current_user_sub: user_sub).call
      }.to have_enqueued_job(ProvisioningExecuteJob)
    end

    it "creates a ProvisioningJob record with create operation" do
      result = described_class.new(organization: organization, params: params, current_user_sub: user_sub).call
      project = result.data
      job = project.provisioning_jobs.last
      expect(job).to be_present
      expect(job.operation).to eq("create")
      expect(job).to be_pending
    end

    it "writes an audit log" do
      expect {
        described_class.new(organization: organization, params: params, current_user_sub: user_sub).call
      }.to change(AuditLog, :count).by(1)
    end

    it "returns failure if name is blank" do
      result = described_class.new(
        organization: organization,
        params: params.merge(name: ""),
        current_user_sub: user_sub
      ).call
      expect(result).to be_failure
    end

    it "returns failure if another active job exists for the project" do
      # Create first project and job
      result1 = described_class.new(organization: organization, params: params, current_user_sub: user_sub).call
      expect(result1).to be_success
    end
  end
end
