require "rails_helper"

RSpec.describe Projects::UpdateService do
  let(:organization) { create(:organization) }
  let(:project) { create(:project, :active, organization: organization) }
  let(:user_sub) { "user-sub-123" }

  describe "#call" do
    context "with metadata-only changes (name, description)" do
      let(:params) { { name: "New Name", description: "New desc" } }

      it "updates the project name without provisioning" do
        result = described_class.new(project: project, params: params, current_user_sub: user_sub).call
        expect(result).to be_success
        expect(project.reload.name).to eq("New Name")
      end

      it "does not create a provisioning job" do
        expect {
          described_class.new(project: project, params: params, current_user_sub: user_sub).call
        }.not_to change(ProvisioningJob, :count)
      end

      it "writes an audit log" do
        expect {
          described_class.new(project: project, params: params, current_user_sub: user_sub).call
        }.to change(AuditLog, :count).by(1)

        log = AuditLog.last
        expect(log.action).to eq("project.update")
        expect(log.user_sub).to eq(user_sub)
      end
    end

    context "with external fields requiring provisioning" do
      let(:params) { { models: [ "gpt-4" ], s3_retention_days: 30 } }

      it "creates a provisioning job with update operation" do
        expect {
          described_class.new(project: project, params: params, current_user_sub: user_sub).call
        }.to change(ProvisioningJob, :count).by(1)

        job = project.provisioning_jobs.last
        expect(job.operation).to eq("update")
        expect(job.status).to eq("pending")
      end

      it "sets project status to update_pending" do
        described_class.new(project: project, params: params, current_user_sub: user_sub).call
        expect(project.reload.status).to eq("update_pending")
      end

      it "enqueues a ProvisioningExecuteJob" do
        expect {
          described_class.new(project: project, params: params, current_user_sub: user_sub).call
        }.to have_enqueued_job(ProvisioningExecuteJob)
      end

      it "seeds provisioning_steps per the update plan" do
        described_class.new(project: project, params: params, current_user_sub: user_sub).call
        job = project.provisioning_jobs.last
        expect(job.provisioning_steps.pluck(:name)).to eq(%w[
          keycloak_client_update
          config_server_apply
          health_check
        ])
      end
    end

    context "when project is deleted" do
      let(:project) { create(:project, :deleted, organization: organization) }

      it "returns failure" do
        result = described_class.new(project: project, params: { name: "New Name" }, current_user_sub: user_sub).call
        expect(result).to be_failure
        expect(result.error).to include("deleted")
      end
    end

    context "with auth config fields (redirect_uris)" do
      let!(:auth_config) { create(:project_auth_config, :oidc, project: project) }
      let(:params) { { redirect_uris: [ "https://app.example.com/cb" ], post_logout_redirect_uris: [ "https://app.example.com" ] } }

      it "persists desired redirect URIs in project_auth_config" do
        described_class.new(project: project, params: params, current_user_sub: user_sub).call
        config = project.project_auth_config.reload
        expect(config.redirect_uris).to eq([ "https://app.example.com/cb" ])
        expect(config.post_logout_redirect_uris).to eq([ "https://app.example.com" ])
      end

      it "does not permit keycloak_client_id or keycloak_client_uuid to be changed" do
        original_uuid = auth_config.keycloak_client_uuid
        described_class.new(
          project: project,
          params: params.merge(keycloak_client_id: "evil", keycloak_client_uuid: "evil-uuid"),
          current_user_sub: user_sub
        ).call
        expect(auth_config.reload.keycloak_client_uuid).to eq(original_uuid)
      end

      it "enqueues a provisioning job for auth config changes" do
        expect {
          described_class.new(project: project, params: params, current_user_sub: user_sub).call
        }.to change(ProvisioningJob, :count).by(1)
      end
    end

    context "when another active provisioning job exists" do
      before do
        create(:provisioning_job, :in_progress, project: project)
      end

      let(:params) { { models: [ "gpt-4" ] } }

      it "returns failure for external field changes" do
        result = described_class.new(project: project, params: params, current_user_sub: user_sub).call
        expect(result).to be_failure
        expect(result.error).to include("provisioning")
      end

      it "still allows metadata-only updates" do
        result = described_class.new(project: project, params: { name: "New Name" }, current_user_sub: user_sub).call
        expect(result).to be_success
      end
    end
  end
end
