require "rails_helper"

RSpec.describe Provisioning::StepSeeder do
  let(:project) { create(:project) }

  describe ".call!" do
    context "when operation is create" do
      let(:job) { create(:provisioning_job, :create, project: project) }

      it "seeds the documented create step plan with order and max_attempts" do
        described_class.call!(job)

        steps = job.provisioning_steps.reload.order(:step_order, :name)
        expect(steps.map(&:name)).to match_array(%w[
          app_registry_register
          keycloak_client_create
          langfuse_project_create
          config_server_apply
          health_check
        ])

        plan_by_name = steps.index_by(&:name)
        expect(plan_by_name["app_registry_register"].step_order).to eq(1)
        expect(plan_by_name["keycloak_client_create"].step_order).to eq(2)
        expect(plan_by_name["langfuse_project_create"].step_order).to eq(2)
        expect(plan_by_name["config_server_apply"].step_order).to eq(3)
        expect(plan_by_name["health_check"].step_order).to eq(4)

        expect(plan_by_name["app_registry_register"].max_retries).to eq(5)
        expect(plan_by_name["keycloak_client_create"].max_retries).to eq(3)
        expect(plan_by_name["health_check"].max_retries).to eq(2)
      end

      it "marks every seeded step pending" do
        described_class.call!(job)
        expect(job.provisioning_steps.reload.all?(&:pending?)).to be(true)
      end
    end

    context "when operation is update" do
      let(:job) { create(:provisioning_job, :update, project: project) }

      it "seeds the update step plan" do
        described_class.call!(job)
        expect(job.provisioning_steps.reload.map(&:name)).to eq(%w[
          keycloak_client_update
          config_server_apply
          health_check
        ])
      end
    end

    context "when operation is delete" do
      let(:job) { create(:provisioning_job, :delete, project: project) }

      it "seeds the delete step plan with parallel teardown" do
        described_class.call!(job)

        steps = job.provisioning_steps.reload.order(:step_order, :name)
        expect(steps.map(&:name)).to match_array(%w[
          config_server_delete
          keycloak_client_delete
          langfuse_project_delete
          app_registry_deregister
          db_cleanup
        ])
        parallel_group = steps.select { |s| s.step_order == 1 }.map(&:name)
        expect(parallel_group).to match_array(%w[
          config_server_delete
          keycloak_client_delete
          langfuse_project_delete
        ])
      end
    end

    context "when called twice" do
      let(:job) { create(:provisioning_job, :create, project: project) }

      it "is idempotent and does not duplicate steps" do
        described_class.call!(job)
        expect { described_class.call!(job) }
          .not_to change { job.provisioning_steps.reload.count }
      end
    end

    context "when operation is unknown" do
      let(:job) { create(:provisioning_job, project: project) }

      it "raises" do
        job.update_column(:operation, "bogus")
        expect { described_class.call!(job) }
          .to raise_error(Provisioning::StepSeeder::UnknownOperationError)
      end
    end
  end
end
