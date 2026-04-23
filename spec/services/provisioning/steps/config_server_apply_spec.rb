require "rails_helper"

RSpec.describe Provisioning::Steps::ConfigServerApply do
  let(:organization) { create(:organization) }
  let(:project) { create(:project, :active, organization: organization) }

  def build_step(job:, params: {})
    step_record = create(:provisioning_step, :config_server_apply, provisioning_job: job)
    described_class.new(step_record: step_record, project: project, params: params)
  end

  describe "#execute" do
    context "when operation is update with no LiteLLM params" do
      let(:job) { create(:provisioning_job, :update, project: project) }

      it "does not apply empty/default LiteLLM config on auth-only update" do
        step = build_step(job: job, params: { redirect_uris: [ "https://example.com/cb" ] })
        result = step.execute
        expect(result[:skipped]).to be(true)
        expect(result[:reason]).to match(/no LiteLLM params/)
      end

      it "does not call Config Server" do
        stub = stub_config_server_apply_changes
        step = build_step(job: job, params: { redirect_uris: [ "https://example.com/cb" ] })
        step.execute
        expect(a_request(:post, /changes/)).not_to have_been_made
      end
    end

    context "when operation is update with LiteLLM params" do
      let(:job) { create(:provisioning_job, :update, project: project) }
      let!(:previous_version) do
        create(:config_version, project: project, version_id: "v-prev-abc",
               snapshot: { "models" => [ "old-model" ], "s3_retention_days" => 30,
                           "s3_path" => "org/proj/", "app_id" => project.app_id })
      end

      it "merges new params on top of the previous snapshot" do
        stub_config_server_apply_changes(version: "v-new-123")
        step = build_step(job: job, params: { models: [ "new-model" ] })
        step.execute
        # Should have sent a request with the merged config (new model, retained s3_retention_days)
        expect(a_request(:post, /changes/).with { |req|
          body = JSON.parse(req.body)
          config = body["config"]
          config["models"] == [ "new-model" ] && config["s3_retention_days"] == 30
        }).to have_been_made
      end

      it "stores previous_version_id in result_snapshot" do
        stub_config_server_apply_changes(version: "v-new-123")
        step = build_step(job: job, params: { models: [ "gpt-4" ] })
        result = step.execute
        expect(result[:previous_version_id]).to eq("v-prev-abc")
        expect(result[:applied]).to be(true)
      end
    end

    context "when operation is create" do
      let(:job) { create(:provisioning_job, :create, project: project) }

      it "applies full LiteLLM config without merging" do
        stub_config_server_apply_changes(version: "v-create-1")
        step = build_step(job: job, params: { models: [ "gpt-4" ], s3_retention_days: 90 })
        result = step.execute
        expect(result[:applied]).to be(true)
        expect(result[:version_id]).to eq("v-create-1")
      end
    end
  end

  describe "#rollback" do
    context "when operation is update and previous_version_id is present" do
      let(:job) { create(:provisioning_job, :update, project: project) }

      it "restores previous config server version instead of deleting config" do
        revert_stub = stub_config_server_revert_changes(version: "v-prev-abc")
        step_record = create(:provisioning_step, :config_server_apply, provisioning_job: job,
                             result_snapshot: { "applied" => true, "previous_version_id" => "v-prev-abc",
                                               "version_id" => "v-new-123" })
        step = described_class.new(step_record: step_record, project: project, params: {})
        step.rollback
        expect(revert_stub).to have_been_requested
      end

      it "does not call delete_changes" do
        stub_config_server_revert_changes(version: "v-prev-abc")
        step_record = create(:provisioning_step, :config_server_apply, provisioning_job: job,
                             result_snapshot: { "applied" => true, "previous_version_id" => "v-prev-abc" })
        step = described_class.new(step_record: step_record, project: project, params: {})
        step.rollback
        expect(a_request(:delete, /changes/)).not_to have_been_made
      end
    end

    context "when operation is create" do
      let(:job) { create(:provisioning_job, :create, project: project) }

      it "calls delete_changes to remove the config" do
        delete_stub = stub_config_server_delete_changes
        step_record = create(:provisioning_step, :config_server_apply, provisioning_job: job,
                             result_snapshot: { "applied" => true, "version_id" => "v-create-1" })
        step = described_class.new(step_record: step_record, project: project, params: {})
        step.rollback
        expect(delete_stub).to have_been_requested
      end
    end

    context "when not yet applied" do
      let(:job) { create(:provisioning_job, :create, project: project) }

      it "does nothing" do
        step_record = create(:provisioning_step, :config_server_apply, provisioning_job: job,
                             result_snapshot: nil)
        step = described_class.new(step_record: step_record, project: project, params: {})
        expect { step.rollback }.not_to raise_error
        expect(a_request(:any, //)).not_to have_been_made
      end
    end
  end
end
