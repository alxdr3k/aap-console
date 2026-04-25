require "rails_helper"

RSpec.describe Provisioning::Steps::LangfuseProjectCreate do
  let(:organization) { create(:organization, langfuse_org_id: "lf-org-1") }
  let(:project)      { create(:project, :provisioning, organization: organization) }
  let(:job)          { create(:provisioning_job, :create, project: project) }

  def build_step(snapshot: nil)
    record = create(:provisioning_step, :langfuse_project_create,
                    provisioning_job: job, result_snapshot: snapshot)
    described_class.new(step_record: record, project: project, params: {})
  end

  describe "#execute (initial create)" do
    before do
      stub_langfuse_create_project(name: "#{organization.slug}-#{project.slug}", project_id: "lf-proj-1")
      stub_langfuse_create_api_key(project_id: "lf-proj-1", public_key: "pk-1", secret_key: "sk-1")
    end

    it "returns the langfuse project id and an ephemeral secret_key" do
      result = build_step.execute
      expect(result[:langfuse_project_id]).to eq("lf-proj-1")
      expect(result[:public_key]).to eq("pk-1")
      expect(result[:_ephemeral][:langfuse_secret_key]).to eq("sk-1")
    end

    it "persists the project side-effect snapshot before minting the key" do
      step = build_step
      step.execute
      step_record = step.send(:step_record).reload
      expect(step_record.result_snapshot["langfuse_project_id"]).to eq("lf-proj-1")
      expect(step_record.result_snapshot["last_api_key_id"]).to be_present
    end
  end

  describe "#execute (resume after crash with no downstream completion)" do
    let(:snapshot) do
      {
        "langfuse_project_id" => "lf-proj-9",
        "langfuse_project_name" => "acme-chatbot",
        "project_created" => true,
        "public_key" => "pk-old",
        "last_api_key_id" => "key-old"
      }
    end

    it "revokes the prior API key and mints a fresh one — secret in :_ephemeral" do
      stub_langfuse_delete_api_key(key_id: "key-old")
      stub_langfuse_create_api_key(project_id: "lf-proj-9", public_key: "pk-new", secret_key: "sk-new")

      result = build_step(snapshot: snapshot).execute

      expect(result[:_ephemeral][:langfuse_secret_key]).to eq("sk-new")
      expect(result["public_key"]).to eq("pk-new")
      expect(result["langfuse_project_id"]).to eq("lf-proj-9")
      expect(WebMock).to have_requested(:post, %r{/api/trpc/projectApiKeys\.create}).once
      expect(WebMock).to have_requested(:post, %r{/api/trpc/projectApiKeys\.delete}).once
    end

    it "tolerates a missing prior key (delete failure)" do
      stub_request(:post, %r{/api/trpc/projectApiKeys\.delete})
        .to_return(status: 404, body: { error: "not found" }.to_json,
                   headers: { "Content-Type" => "application/json" })
      stub_langfuse_create_api_key(project_id: "lf-proj-9", public_key: "pk-new", secret_key: "sk-new")

      expect { build_step(snapshot: snapshot).execute }.not_to raise_error
    end
  end

  describe "#already_completed?" do
    it "returns false when no snapshot" do
      expect(build_step.already_completed?).to be(false)
    end

    it "returns false when langfuse project exists but config_server_apply has not persisted" do
      snap = { "langfuse_project_id" => "lf-proj-1" }
      step = build_step(snapshot: snap)
      create(:provisioning_step, :config_server_apply,
             provisioning_job: job, result_snapshot: { "applied" => true, "local_persisted" => false })
      expect(step.already_completed?).to be(false)
    end

    it "returns true only after config_server_apply has fully persisted" do
      snap = { "langfuse_project_id" => "lf-proj-1" }
      step = build_step(snapshot: snap)
      create(:provisioning_step, :config_server_apply,
             provisioning_job: job, result_snapshot: { "applied" => true, "local_persisted" => true })
      expect(step.already_completed?).to be(true)
    end
  end

  describe "#rollback" do
    let(:snapshot) do
      { "langfuse_project_id" => "lf-proj-9", "last_api_key_id" => "key-9" }
    end

    it "deletes the API key and the langfuse project" do
      stub_langfuse_delete_api_key(key_id: "key-9")
      stub_langfuse_delete_project(project_id: "lf-proj-9")
      build_step(snapshot: snapshot).rollback
      expect(WebMock).to have_requested(:post, %r{/api/trpc/projects\.delete}).once
    end

    it "no-ops when there is no langfuse_project_id" do
      expect { build_step.rollback }.not_to raise_error
    end
  end
end
