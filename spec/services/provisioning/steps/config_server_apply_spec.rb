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

    context "when external apply succeeds but the local ConfigVersion insert raises" do
      let(:job) { create(:provisioning_job, :create, project: project) }

      it "persists the side-effect snapshot to the step before raising so RollbackRunner can undo the external change" do
        stub_config_server_apply_changes(version: "v-leak-1")
        allow(ConfigVersion).to receive(:create!).and_raise(
          ActiveRecord::RecordInvalid.new(ConfigVersion.new)
        )

        step_record = create(:provisioning_step, :config_server_apply, provisioning_job: job)
        step = described_class.new(step_record: step_record, project: project,
                                   params: { models: [ "gpt-4" ], s3_retention_days: 90 })

        expect { step.execute }.to raise_error(ActiveRecord::RecordInvalid)

        step_record.reload
        expect(step_record.result_snapshot).to include("applied" => true,
                                                      "local_persisted" => false,
                                                      "version_id" => "v-leak-1")
      end
    end

    context "resume path (snapshot with applied: true but local_persisted: false)" do
      let(:job) { create(:provisioning_job, :create, project: project) }

      it "completes local persistence without re-calling Config Server" do
        step_record = create(:provisioning_step, :config_server_apply, provisioning_job: job,
                             result_snapshot: {
                               "applied" => true,
                               "local_persisted" => false,
                               "version_id" => "v-resume-1",
                               "previous_version_id" => nil,
                               "config_snapshot" => {
                                 "models" => [ "gpt-4" ],
                                 "s3_retention_days" => 90,
                                 "s3_path" => "#{organization.slug}/#{project.slug}/",
                                 "app_id" => project.app_id
                               }
                             })
        step = described_class.new(step_record: step_record, project: project, params: {})

        expect {
          result = step.execute
          expect(result["local_persisted"]).to be(true)
          expect(result["version_id"]).to eq("v-resume-1")
        }.to change(ConfigVersion, :count).by(1)

        expect(a_request(:post, /changes/)).not_to have_been_made
        cv = project.config_versions.find_by(version_id: "v-resume-1")
        expect(cv.snapshot["models"]).to eq([ "gpt-4" ])
      end

      it "is idempotent if the ConfigVersion already exists (no duplicate row)" do
        create(:config_version, project: project, version_id: "v-resume-1",
               snapshot: { "models" => [ "gpt-4" ] })

        step_record = create(:provisioning_step, :config_server_apply, provisioning_job: job,
                             result_snapshot: {
                               "applied" => true,
                               "local_persisted" => false,
                               "version_id" => "v-resume-1",
                               "config_snapshot" => { "models" => [ "gpt-4" ] }
                             })
        step = described_class.new(step_record: step_record, project: project, params: {})

        expect { step.execute }.not_to change(ConfigVersion, :count)
      end
    end

    context "secrets are never stored in result_snapshot" do
      let(:job) { create(:provisioning_job, :create, project: project) }

      it "does not include Langfuse SDK keys or other secrets in config_snapshot" do
        stub_config_server_apply_changes(version: "v-no-secret-1")
        create(:provisioning_step,
               provisioning_job: job,
               name: "langfuse_project_create",
               step_order: 2,
               status: :completed,
               result_snapshot: { "public_key" => "pk-lf-aaa", "langfuse_project_id" => "lf-1" })

        step_record = create(:provisioning_step, :config_server_apply, provisioning_job: job)
        step = described_class.new(step_record: step_record, project: project,
                                   params: { models: [ "gpt-4" ], s3_retention_days: 90,
                                             langfuse_secret_key: "sk-lf-should-never-persist" })

        step.execute
        step_record.reload

        persisted = step_record.result_snapshot.to_json
        expect(persisted).not_to include("sk-lf-should-never-persist")
        expect(persisted).not_to include("pk-lf-aaa")
        expect(persisted).not_to include("LANGFUSE_SECRET_KEY")
        expect(persisted).not_to include("LANGFUSE_PUBLIC_KEY")
      end
    end

    describe "#already_completed?" do
      let(:job) { create(:provisioning_job, :create, project: project) }

      it "returns false when snapshot has applied: true but local_persisted: false" do
        step_record = create(:provisioning_step, :config_server_apply, provisioning_job: job,
                             result_snapshot: { "applied" => true, "local_persisted" => false,
                                               "version_id" => "v-half" })
        step = described_class.new(step_record: step_record, project: project, params: {})
        expect(step.already_completed?).to be(false)
      end

      it "returns true only when both applied and local_persisted are true" do
        step_record = create(:provisioning_step, :config_server_apply, provisioning_job: job,
                             result_snapshot: { "applied" => true, "local_persisted" => true,
                                               "version_id" => "v-whole" })
        step = described_class.new(step_record: step_record, project: project, params: {})
        expect(step.already_completed?).to be(true)
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

      it "records a rollback ConfigVersion so subsequent updates use the correct base" do
        stub_config_server_revert_changes(version: "v-prev-abc")
        prior_cv = create(:config_version, project: project, version_id: "v-prev-abc",
                          snapshot: { "models" => [ "gpt-3.5" ], "s3_retention_days" => 30 })
        step_record = create(:provisioning_step, :config_server_apply, provisioning_job: job,
                             result_snapshot: { "applied" => true, "previous_version_id" => "v-prev-abc",
                                               "version_id" => "v-new-123" })
        step = described_class.new(step_record: step_record, project: project, params: {})

        expect { step.rollback }.to change(ConfigVersion, :count).by(1)

        rollback_cv = project.config_versions.order(:created_at).last
        expect(rollback_cv.change_type).to eq("rollback")
        expect(rollback_cv.version_id).to eq("v-prev-abc")
        expect(rollback_cv.snapshot).to eq(prior_cv.snapshot)
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

    context "when Config Server returns a server error on revert (update operation)" do
      let(:job) { create(:provisioning_job, :update, project: project) }

      it "re-raises BaseClient::ApiError so RollbackRunner can mark the step rollback_failed" do
        stub_config_server_revert_changes_failure(status: 500)
        step_record = create(:provisioning_step, :config_server_apply, provisioning_job: job,
                             result_snapshot: { "applied" => true, "previous_version_id" => "v-prev-abc",
                                               "version_id" => "v-new-123" })
        step = described_class.new(step_record: step_record, project: project, params: {})
        expect { step.rollback }.to raise_error(BaseClient::ApiError)
      end
    end

    context "when Config Server returns a server error on delete (create operation)" do
      let(:job) { create(:provisioning_job, :create, project: project) }

      it "re-raises BaseClient::ApiError so RollbackRunner can mark the step rollback_failed" do
        stub_config_server_delete_changes_failure(status: 500)
        step_record = create(:provisioning_step, :config_server_apply, provisioning_job: job,
                             result_snapshot: { "applied" => true, "version_id" => "v-create-1" })
        step = described_class.new(step_record: step_record, project: project, params: {})
        expect { step.rollback }.to raise_error(BaseClient::ApiError)
      end
    end
  end
end
