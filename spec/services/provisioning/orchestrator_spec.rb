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

    context "when an update job fails" do
      let(:job) { create(:provisioning_job, :pending, project: project, operation: "update") }

      before do
        project.update!(status: :update_pending)
        Provisioning::StepSeeder.call!(job)
      end

      it "transitions project out of update_pending on failure" do
        allow_any_instance_of(Provisioning::StepRunner).to receive(:execute) do |runner|
          step_record = runner.instance_variable_get(:@step)
          if step_record.name == "keycloak_client_update"
            { status: :failed, step: step_record, error: StandardError.new("keycloak down") }
          else
            { status: :completed, step: step_record, ephemeral_params: {} }
          end
        end

        expect_any_instance_of(Provisioning::RollbackRunner).to receive(:run).and_return(true)

        described_class.new(provisioning_job: job).run

        expect(job.reload.status).to eq("rolled_back")
        expect(project.reload.status).to eq("active")
      end

      it "leaves project in update_pending when rollback itself fails" do
        allow_any_instance_of(Provisioning::StepRunner).to receive(:execute) do |runner|
          step_record = runner.instance_variable_get(:@step)
          if step_record.name == "keycloak_client_update"
            { status: :failed, step: step_record, error: StandardError.new("keycloak down") }
          else
            { status: :completed, step: step_record, ephemeral_params: {} }
          end
        end

        expect_any_instance_of(Provisioning::RollbackRunner).to receive(:run).and_return(false)

        described_class.new(provisioning_job: job).run

        expect(job.reload.status).to eq("rollback_failed")
        expect(project.reload.status).to eq("update_pending")
      end
    end

    context "when Config Server rollback fails (no RollbackRunner stub — full propagation path)" do
      let(:update_job) { create(:provisioning_job, :pending, project: project, operation: "update") }

      before do
        project.update!(status: :update_pending)
        Provisioning::StepSeeder.call!(update_job)

        # Pre-complete config_server_apply to simulate that it ran successfully before the
        # forward failure occurred. RollbackRunner will find this step and attempt to revert it.
        update_job.provisioning_steps.find_by(name: "config_server_apply").update!(
          status: :completed,
          result_snapshot: {
            "applied" => true,
            "previous_version_id" => "v-prev-1",
            "version_id" => "v-new-1"
          }
        )
      end

      it "marks job rollback_failed and leaves project in update_pending" do
        allow_any_instance_of(Provisioning::StepRunner).to receive(:execute) do |runner|
          step_record = runner.instance_variable_get(:@step)
          { status: :failed, step: step_record, error: StandardError.new("keycloak down") }
        end

        stub_config_server_revert_changes_failure(status: 500)

        described_class.new(provisioning_job: update_job).run

        expect(update_job.reload.status).to eq("rollback_failed")
        expect(project.reload.status).to eq("update_pending")

        config_step = update_job.provisioning_steps.find_by(name: "config_server_apply")
        expect(config_step.reload.status).to eq("rollback_failed")
      end
    end
  end
end
