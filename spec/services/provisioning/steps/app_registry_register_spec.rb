require "rails_helper"

RSpec.describe Provisioning::Steps::AppRegistryRegister do
  let(:organization) { create(:organization) }
  let(:project)      { create(:project, :provisioning, organization: organization) }
  let(:job)          { create(:provisioning_job, :create, project: project) }

  def build_step(snapshot: nil)
    record = create(:provisioning_step, :app_registry_register,
                    provisioning_job: job, result_snapshot: snapshot)
    described_class.new(step_record: record, project: project, params: {})
  end

  describe "#execute" do
    it "persists the side-effect snapshot before returning" do
      stub_config_server_app_registry_webhook
      step = build_step
      step.execute
      step_record = step.send(:step_record).reload
      expect(step_record.result_snapshot["registered"]).to be(true)
      expect(step_record.result_snapshot["app_id"]).to eq(project.app_id)
    end
  end

  describe "#already_completed?" do
    it "returns true when snapshot has registered: true" do
      step = build_step(snapshot: { "registered" => true, "app_id" => project.app_id })
      expect(step.already_completed?).to be(true)
    end

    it "returns false otherwise" do
      expect(build_step.already_completed?).to be(false)
    end
  end

  describe "#rollback" do
    it "calls Config Server webhook with action: delete when registered" do
      stub = stub_config_server_app_registry_webhook
      build_step(snapshot: { "registered" => true, "app_id" => project.app_id }).rollback
      expect(WebMock).to have_requested(:post, %r{/api/v1/admin/app-registry/webhook}).at_least_once
    end

    it "no-ops when nothing was registered" do
      expect { build_step.rollback }.not_to raise_error
    end
  end
end
