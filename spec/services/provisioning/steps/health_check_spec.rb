require "rails_helper"

RSpec.describe Provisioning::Steps::HealthCheck do
  let(:organization) { create(:organization, langfuse_org_id: "lf-org-1") }
  let(:project) { create(:project, :active, organization: organization) }
  let(:job) { create(:provisioning_job, :create, project: project) }
  let(:step_record) { create(:provisioning_step, :health_check, provisioning_job: job) }
  let(:auth_config) do
    create(
      :project_auth_config,
      :oidc,
      project: project,
      keycloak_client_id: "aap-#{organization.slug}-#{project.slug}-oidc",
      keycloak_client_uuid: "kc-client-1"
    )
  end
  let(:config_snapshot) do
    {
      "models" => [ "gpt-4.1" ],
      "guardrails" => [ { "name" => "default" } ],
      "s3_path" => "#{organization.slug}/#{project.slug}/",
      "s3_retention_days" => 90,
      "app_id" => project.app_id
    }
  end

  def build_step
    described_class.new(step_record: step_record, project: project, params: {})
  end

  def create_completed_dependency_steps
    auth_config
    create(
      :provisioning_step,
      :keycloak_client_create,
      :completed,
      provisioning_job: job,
      result_snapshot: {
        "keycloak_client_id" => auth_config.keycloak_client_id,
        "keycloak_client_uuid" => auth_config.keycloak_client_uuid
      }
    )
    create(
      :provisioning_step,
      :langfuse_project_create,
      :completed,
      provisioning_job: job,
      result_snapshot: {
        "langfuse_project_id" => "lf-proj-1",
        "public_key" => "pk-lf-1"
      }
    )
    create(
      :provisioning_step,
      :config_server_apply,
      :completed,
      provisioning_job: job,
      result_snapshot: {
        "applied" => true,
        "local_persisted" => true,
        "version_id" => "v-1",
        "config_snapshot" => config_snapshot
      }
    )
  end

  def stub_langfuse_list_api_keys(project_id:, keys:)
    stub_langfuse_login
    stub_request(:post, "#{LangfuseMock::TRPC_BASE}/projectApiKeys.byProjectId")
      .to_return(
        status: 200,
        body: { result: { data: keys } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  describe "#execute" do
    it "verifies Keycloak, LiteLLM config, and Langfuse consistency through service-specific read paths" do
      create_completed_dependency_steps
      stub_keycloak_get_clients(
        client_id: auth_config.keycloak_client_id,
        clients: [ { "id" => auth_config.keycloak_client_uuid, "clientId" => auth_config.keycloak_client_id } ]
      )
      stub_config_server_get_config(
        org: organization.slug,
        project: project.slug,
        service: "litellm",
        config: config_snapshot
      )
      stub_langfuse_list_api_keys(
        project_id: "lf-proj-1",
        keys: [ { "id" => "lf-key-1", "publicKey" => "pk-lf-1" } ]
      )

      result = build_step.execute

      expect(result[:passed]).to be(true)
      expect(result[:checks][:keycloak]).to include(status: "ok", client_id: auth_config.keycloak_client_id)
      expect(result[:checks][:litellm]).to include(status: "ok", version_id: "v-1")
      expect(result[:checks][:langfuse]).to include(status: "ok", project_id: "lf-proj-1")
      expect(WebMock).to have_requested(:get, "#{KeycloakMock::BASE}/clients")
        .with(query: hash_including("clientId" => auth_config.keycloak_client_id)).once
      expect(WebMock).to have_requested(:get, "#{ConfigServerMock::CONFIG_SERVER_URL}/api/v1/config")
        .with(query: hash_including("org" => organization.slug, "project" => project.slug, "service" => "litellm")).once
      expect(WebMock).to have_requested(:post, "#{LangfuseMock::TRPC_BASE}/projectApiKeys.byProjectId").once
    end

    it "records a warning when LiteLLM config does not match the applied snapshot" do
      create_completed_dependency_steps
      stub_keycloak_get_clients(
        client_id: auth_config.keycloak_client_id,
        clients: [ { "id" => auth_config.keycloak_client_uuid, "clientId" => auth_config.keycloak_client_id } ]
      )
      stub_config_server_get_config(
        org: organization.slug,
        project: project.slug,
        service: "litellm",
        config: config_snapshot.merge("models" => [ "wrong-model" ])
      )
      stub_langfuse_list_api_keys(
        project_id: "lf-proj-1",
        keys: [ { "id" => "lf-key-1", "publicKey" => "pk-lf-1" } ]
      )

      expect { build_step.execute }.to raise_error(/LiteLLM config mismatch/)
      expect(job.reload.warnings).to include(
        hash_including("step" => "health_check", "message" => /LiteLLM config mismatch/)
      )
    end

    it "records a warning when the expected Langfuse public key is missing" do
      create_completed_dependency_steps
      stub_keycloak_get_clients(
        client_id: auth_config.keycloak_client_id,
        clients: [ { "id" => auth_config.keycloak_client_uuid, "clientId" => auth_config.keycloak_client_id } ]
      )
      stub_config_server_get_config(
        org: organization.slug,
        project: project.slug,
        service: "litellm",
        config: config_snapshot
      )
      stub_langfuse_list_api_keys(project_id: "lf-proj-1", keys: [])

      expect { build_step.execute }.to raise_error(/Langfuse API key missing/)
      expect(job.reload.warnings).to include(
        hash_including("step" => "health_check", "message" => /Langfuse API key missing/)
      )
    end

    it "skips LiteLLM readback when Config Server apply was skipped for an auth-only update" do
      auth_config
      update_job = create(:provisioning_job, :update, project: project)
      update_health_check = create(:provisioning_step, :health_check, provisioning_job: update_job)
      create(
        :provisioning_step,
        :config_server_apply,
        :completed,
        provisioning_job: update_job,
        result_snapshot: { "skipped" => true, "reason" => "no LiteLLM params in update operation" }
      )
      stub_keycloak_get_clients(
        client_id: auth_config.keycloak_client_id,
        clients: [ { "id" => auth_config.keycloak_client_uuid, "clientId" => auth_config.keycloak_client_id } ]
      )

      result = described_class.new(step_record: update_health_check, project: project, params: {}).execute

      expect(result[:checks][:litellm]).to include(status: "skipped")
      expect(a_request(:get, "#{ConfigServerMock::CONFIG_SERVER_URL}/api/v1/config")).not_to have_been_made
    end
  end
end
