require "rails_helper"

RSpec.describe Projects::DestroyService do
  let(:organization) { create(:organization) }
  let(:project) { create(:project, :active, organization: organization) }
  let(:user_sub) { "user-sub-123" }

  describe "#call" do
    it "sets project status to deleting" do
      described_class.new(project: project, current_user_sub: user_sub).call
      expect(project.reload.status).to eq("deleting")
    end

    it "creates a provisioning job with delete operation" do
      expect {
        described_class.new(project: project, current_user_sub: user_sub).call
      }.to change(ProvisioningJob, :count).by(1)

      job = project.provisioning_jobs.last
      expect(job.operation).to eq("delete")
      expect(job.status).to eq("pending")
    end

    it "enqueues a ProvisioningExecuteJob" do
      expect {
        described_class.new(project: project, current_user_sub: user_sub).call
      }.to have_enqueued_job(ProvisioningExecuteJob)
    end

    it "seeds provisioning_steps per the delete plan" do
      described_class.new(project: project, current_user_sub: user_sub).call
      job = project.provisioning_jobs.last
      expect(job.provisioning_steps.pluck(:name)).to match_array(%w[
        config_server_delete
        keycloak_client_delete
        langfuse_project_delete
        app_registry_deregister
        db_cleanup
      ])
    end

    it "writes an audit log" do
      expect {
        described_class.new(project: project, current_user_sub: user_sub).call
      }.to change(AuditLog, :count).by(1)

      log = AuditLog.last
      expect(log.action).to eq("project.destroy")
      expect(log.user_sub).to eq(user_sub)
    end

    it "returns failure when project is already deleted" do
      project.update!(status: :deleted)
      result = described_class.new(project: project, current_user_sub: user_sub).call
      expect(result).to be_failure
      expect(result.error).to include("deleted")
    end

    it "returns failure when another active job exists" do
      create(:provisioning_job, :in_progress, project: project)
      result = described_class.new(project: project, current_user_sub: user_sub).call
      expect(result).to be_failure
      expect(result.error).to include("provisioning")
    end
  end
end
