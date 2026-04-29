require "rails_helper"

RSpec.describe Projects::CreateService do
  let(:organization) { create(:organization) }
  let(:user_sub) { "user-sub-admin" }
  let(:params) do
    {
      name: "Chatbot",
      description: "Our AI chatbot",
      auth_type: "oidc",
      models: [ "azure-gpt4" ],
      guardrails: [ "content-filter" ],
      s3_retention_days: 90
    }
  end

  describe "#call" do
    it "creates the project in DB with status provisioning" do
      result = described_class.new(organization: organization, params: params, current_user_sub: user_sub).call
      expect(result).to be_success
      project = result.data
      expect(project).to be_persisted
      expect(project.name).to eq("Chatbot")
      expect(project).to be_provisioning
    end

    it "auto-generates an app_id" do
      result = described_class.new(organization: organization, params: params, current_user_sub: user_sub).call
      expect(result.data.app_id).to match(/\Aapp-[a-zA-Z0-9]{12}\z/)
    end

    it "enqueues a ProvisioningExecuteJob" do
      expect {
        described_class.new(organization: organization, params: params, current_user_sub: user_sub).call
      }.to have_enqueued_job(ProvisioningExecuteJob)
    end

    it "forwards create config inputs to the provisioning execution job" do
      expect {
        described_class.new(organization: organization, params: params, current_user_sub: user_sub).call
      }.to have_enqueued_job(ProvisioningExecuteJob).with(
        kind_of(Integer),
        hash_including(
          auth_type: "oidc",
          models: [ "azure-gpt4" ],
          guardrails: [ "content-filter" ],
          s3_retention_days: 90,
          current_user_sub: user_sub
        )
      )
    end

    it "creates a ProvisioningJob record with create operation" do
      result = described_class.new(organization: organization, params: params, current_user_sub: user_sub).call
      project = result.data
      job = project.provisioning_jobs.last
      expect(job).to be_present
      expect(job.operation).to eq("create")
      expect(job).to be_pending
    end

    it "seeds provisioning_steps according to the create plan" do
      result = described_class.new(organization: organization, params: params, current_user_sub: user_sub).call
      job = result.data.provisioning_jobs.last
      expect(job.provisioning_steps.pluck(:name)).to match_array(%w[
        app_registry_register
        keycloak_client_create
        langfuse_project_create
        config_server_apply
        health_check
      ])
    end

    it "writes an audit log" do
      expect {
        described_class.new(organization: organization, params: params, current_user_sub: user_sub).call
      }.to change(AuditLog, :count).by(1)
    end

    it "returns failure if name is blank" do
      result = described_class.new(
        organization: organization,
        params: params.merge(name: ""),
        current_user_sub: user_sub
      ).call
      expect(result).to be_failure
    end

    it "creates a project_auth_config with the given auth_type" do
      result = described_class.new(organization: organization, params: params, current_user_sub: user_sub).call
      expect(result).to be_success
      auth_config = result.data.project_auth_config
      expect(auth_config).to be_present
      expect(auth_config.auth_type).to eq("oidc")
    end

    it "assigns a deterministic aap-prefixed keycloak_client_id for OIDC" do
      organization.update!(slug: "acme")
      result = described_class.new(
        organization: organization,
        params: params,
        current_user_sub: user_sub
      ).call
      expect(result).to be_success
      auth_config = result.data.project_auth_config
      expect(auth_config.keycloak_client_id).to start_with("aap-acme-")
      expect(auth_config.keycloak_client_id).to end_with("-oidc")
    end

    it "leaves keycloak_client_id null when auth_type is PAK" do
      result = described_class.new(
        organization: organization,
        params: params.merge(auth_type: "pak"),
        current_user_sub: user_sub
      ).call
      expect(result).to be_success
      expect(result.data.project_auth_config.keycloak_client_id).to be_nil
    end

    %w[saml oauth].each do |auth_type|
      it "assigns a deterministic aap-prefixed keycloak_client_id for #{auth_type.upcase}" do
        organization.update!(slug: "acme")
        result = described_class.new(
          organization: organization,
          params: params.merge(auth_type: auth_type),
          current_user_sub: user_sub
        ).call

        expect(result).to be_success
        auth_config = result.data.project_auth_config
        expect(auth_config.keycloak_client_id).to start_with("aap-acme-")
        expect(auth_config.keycloak_client_id).to end_with("-#{auth_type}")
      end
    end

    it "returns failure if another active job exists for the project" do
      # Create first project and job
      result1 = described_class.new(organization: organization, params: params, current_user_sub: user_sub).call
      expect(result1).to be_success
    end
  end
end
