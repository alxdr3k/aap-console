require "rails_helper"

RSpec.describe Provisioning::RollbackRunner do
  let(:organization) { create(:organization) }
  let(:project) { create(:project, :active, organization: organization) }
  let(:job) { create(:provisioning_job, :pending, project: project, operation: "create") }

  describe "#run" do
    context "when all step rollbacks succeed" do
      it "marks each step rolled_back and returns true" do
        step = create(:provisioning_step, :config_server_apply, :completed, provisioning_job: job,
                      result_snapshot: nil)

        # Step impl rollback is a no-op when snapshot is nil (already_applied? == false)
        runner = described_class.new(provisioning_job: job)
        result = runner.run

        expect(result).to be(true)
        expect(step.reload.status).to eq("rolled_back")
      end

      it "processes steps in reverse step_order" do
        order_log = []

        step1 = create(:provisioning_step, provisioning_job: job, name: "app_registry_register",
                       step_order: 1, status: :completed, result_snapshot: nil)
        step2 = create(:provisioning_step, provisioning_job: job, name: "config_server_apply",
                       step_order: 3, status: :completed, result_snapshot: nil)

        allow_any_instance_of(Provisioning::Steps::AppRegistryRegister).to receive(:rollback) {
          order_log << step1.name
        }
        allow_any_instance_of(Provisioning::Steps::ConfigServerApply).to receive(:rollback) {
          order_log << step2.name
        }

        described_class.new(provisioning_job: job).run

        expect(order_log).to eq([ "config_server_apply", "app_registry_register" ])
      end
    end

    context "when a step rollback raises BaseClient::ApiError" do
      it "marks that step rollback_failed and returns false" do
        step = create(:provisioning_step, :config_server_apply, :completed, provisioning_job: job,
                      result_snapshot: { "applied" => true, "version_id" => "v-abc" })

        allow_any_instance_of(Provisioning::Steps::ConfigServerApply)
          .to receive(:rollback)
          .and_raise(BaseClient::ServerError.new("Config Server 500"))

        runner = described_class.new(provisioning_job: job)
        result = runner.run

        expect(result).to be(false)
        expect(step.reload.status).to eq("rollback_failed")
        expect(step.reload.error_message).to match(/Config Server 500/)
      end
    end

    context "when a step rollback raises a generic error" do
      it "marks that step rollback_failed and returns false" do
        step = create(:provisioning_step, :keycloak_client_create, :completed, provisioning_job: job,
                      result_snapshot: { "keycloak_client_uuid" => "uuid-1" })

        allow_any_instance_of(Provisioning::Steps::KeycloakClientCreate)
          .to receive(:rollback)
          .and_raise(StandardError.new("unexpected"))

        runner = described_class.new(provisioning_job: job)
        result = runner.run

        expect(result).to be(false)
        expect(step.reload.status).to eq("rollback_failed")
      end
    end

    context "when only skipped steps exist" do
      it "treats them the same as completed and returns true" do
        step = create(:provisioning_step, :config_server_apply, provisioning_job: job,
                      status: :skipped, result_snapshot: nil)

        result = described_class.new(provisioning_job: job).run

        expect(result).to be(true)
        expect(step.reload.status).to eq("rolled_back")
      end
    end

    context "when no completed or skipped steps exist" do
      it "returns true without doing anything" do
        create(:provisioning_step, :config_server_apply, :pending, provisioning_job: job)

        result = described_class.new(provisioning_job: job).run

        expect(result).to be(true)
      end
    end

    context "when a failed step left a side-effect snapshot (atomicity gap recovery)" do
      it "still rolls back the external side effect" do
        step = create(:provisioning_step, :config_server_apply, :failed, provisioning_job: job,
                      result_snapshot: { "applied" => true, "version_id" => "v-leak" })

        rollback_called = false
        allow_any_instance_of(Provisioning::Steps::ConfigServerApply).to receive(:rollback) {
          rollback_called = true
        }

        result = described_class.new(provisioning_job: job).run

        expect(result).to be(true)
        expect(rollback_called).to be(true)
        expect(step.reload.status).to eq("rolled_back")
      end

      it "ignores failed steps that have no snapshot (no external side effect)" do
        step = create(:provisioning_step, :config_server_apply, :failed, provisioning_job: job,
                      result_snapshot: nil)

        expect_any_instance_of(Provisioning::Steps::ConfigServerApply).not_to receive(:rollback)

        result = described_class.new(provisioning_job: job).run

        expect(result).to be(true)
        expect(step.reload.status).to eq("failed")
      end
    end
  end
end
