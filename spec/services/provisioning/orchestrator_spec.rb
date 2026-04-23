require "rails_helper"

RSpec.describe Provisioning::Orchestrator do
  let(:organization) { create(:organization) }
  let(:project) { create(:project, :provisioning, organization: organization) }
  let(:job) { create(:provisioning_job, :pending, project: project, operation: "create") }

  describe "#run" do
    context "when no provisioning_steps have been seeded" do
      it "fails fast with rollback path and never marks the project active" do
        described_class.new(provisioning_job: job).run

        expect(job.reload.status).to eq("failed")
        expect(job.error_message).to match(/no provisioning steps/i)
        expect(project.reload.status).to eq("provision_failed")
      end
    end

    context "when every step succeeds" do
      before do
        Provisioning::StepSeeder.call!(job)
      end

      it "marks the job completed and the project active" do
        allow_any_instance_of(Provisioning::StepRunner).to receive(:execute).and_return(
          { status: :completed, step: instance_double("ProvisioningStep"), ephemeral_params: {} }
        )

        described_class.new(provisioning_job: job).run

        expect(job.reload.status).to eq("completed")
        expect(project.reload.status).to eq("active")
      end
    end

    context "when a fatal step fails" do
      before do
        Provisioning::StepSeeder.call!(job)
      end

      it "invokes rollback and transitions project to provision_failed" do
        failing_step = job.provisioning_steps.find_by(name: "keycloak_client_create")

        call_count = 0
        allow_any_instance_of(Provisioning::StepRunner).to receive(:execute) do |runner|
          call_count += 1
          step_record = runner.instance_variable_get(:@step)
          if step_record.name == "keycloak_client_create"
            { status: :failed, step: step_record, error: StandardError.new("boom") }
          else
            { status: :completed, step: step_record, ephemeral_params: {} }
          end
        end

        expect_any_instance_of(Provisioning::RollbackRunner).to receive(:run).and_return(true)

        described_class.new(provisioning_job: job).run

        expect(job.reload.status).to eq("rolled_back")
        expect(project.reload.status).to eq("provision_failed")
      end
    end

    context "when only health_check fails" do
      before do
        Provisioning::StepSeeder.call!(job)
      end

      it "completes with warnings without triggering rollback" do
        allow_any_instance_of(Provisioning::StepRunner).to receive(:execute) do |runner|
          step_record = runner.instance_variable_get(:@step)
          if step_record.name == "health_check"
            { status: :failed, step: step_record, error: StandardError.new("unhealthy") }
          else
            { status: :completed, step: step_record, ephemeral_params: {} }
          end
        end

        expect_any_instance_of(Provisioning::RollbackRunner).not_to receive(:run)

        described_class.new(provisioning_job: job).run

        expect(job.reload.status).to eq("completed_with_warnings")
        expect(project.reload.status).to eq("active")
      end
    end

    context "when an orchestration-level exception leaks from a step runner" do
      before do
        Provisioning::StepSeeder.call!(job)
      end

      it "routes through rollback rather than silently failing" do
        allow_any_instance_of(Provisioning::StepRunner).to receive(:execute).and_raise("unexpected")

        expect_any_instance_of(Provisioning::RollbackRunner).to receive(:run).and_return(true)

        described_class.new(provisioning_job: job).run

        expect(job.reload.status).to eq("rolled_back")
        expect(project.reload.status).to eq("provision_failed")
      end
    end
  end
end
