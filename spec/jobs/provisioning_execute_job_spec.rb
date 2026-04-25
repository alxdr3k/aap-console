require "rails_helper"

RSpec.describe ProvisioningExecuteJob, type: :job do
  let(:project) { create(:project, :provisioning) }
  let(:job)     { create(:provisioning_job, :create, project: project) }

  describe "#perform input_snapshot fallback" do
    it "uses provisioning_jobs.input_snapshot when no params are passed (manual retry)" do
      job.update!(input_snapshot: { "auth_type" => "oidc", "models" => [ "gpt-4" ] })

      orchestrator = instance_double(Provisioning::Orchestrator, run: nil)
      expect(Provisioning::Orchestrator).to receive(:new).with(
        provisioning_job: job,
        params: { auth_type: "oidc", models: [ "gpt-4" ] },
        current_user_sub: "user-1"
      ).and_return(orchestrator)

      described_class.new.perform(job.id, current_user_sub: "user-1")
    end

    it "prefers explicit params over input_snapshot when both are present" do
      job.update!(input_snapshot: { "auth_type" => "saml" })

      orchestrator = instance_double(Provisioning::Orchestrator, run: nil)
      expect(Provisioning::Orchestrator).to receive(:new).with(
        provisioning_job: job,
        params: { auth_type: "oidc" },
        current_user_sub: nil
      ).and_return(orchestrator)

      described_class.new.perform(job.id, auth_type: "oidc")
    end

    it "passes empty params when there is neither input_snapshot nor explicit params" do
      orchestrator = instance_double(Provisioning::Orchestrator, run: nil)
      expect(Provisioning::Orchestrator).to receive(:new).with(
        provisioning_job: job,
        params: {},
        current_user_sub: nil
      ).and_return(orchestrator)

      described_class.new.perform(job.id)
    end
  end

  describe "#perform terminal-state guard" do
    ProvisioningJob::TERMINAL_STATUSES.each do |status|
      it "no-ops when status is #{status}" do
        job.update!(status: status)
        expect(Provisioning::Orchestrator).not_to receive(:new)
        expect { described_class.new.perform(job.id) }.not_to raise_error
      end
    end

    it "runs the orchestrator when status is pending" do
      job.update!(status: :pending)
      orchestrator = instance_double(Provisioning::Orchestrator, run: nil)
      expect(Provisioning::Orchestrator).to receive(:new).and_return(orchestrator)
      described_class.new.perform(job.id)
    end
  end
end
