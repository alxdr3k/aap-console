require "rails_helper"

RSpec.describe AuthConfigs::RegenerateClientSecretService do
  let(:organization) { create(:organization) }
  let(:project) { create(:project, :active, organization: organization) }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let!(:auth_config) do
    create(:project_auth_config,
           :oidc,
           project: project,
           keycloak_client_id: "aap-acme-chatbot-oidc",
           keycloak_client_uuid: "uuid-123")
  end

  before { allow(Rails).to receive(:cache).and_return(cache) }

  it "regenerates the client secret, caches it, and writes an audit log" do
    stub_keycloak_regenerate_client_secret(uuid: "uuid-123", secret: "new-client-secret")

    result = described_class.new(project: project, current_user_sub: "user-sub-123").call

    expect(result).to be_success
    expect(result.data[:cache_failed]).to be(false)
    expect(result.data[:reveal_payload].dig("secrets", "client_secret", "value")).to eq("new-client-secret")
    expect(AuthConfigs::SecretRevealCache.read(project).dig("secrets", "client_secret", "value")).to eq("new-client-secret")
    audit = project.audit_logs.order(:id).last
    expect(audit.action).to eq("auth_config.secret_regenerated")
    expect(audit.details["cache_failed"]).to be(false)
  end

  it "returns failure when another provisioning job is active" do
    create(:provisioning_job, :in_progress, project: project, operation: "update")

    result = described_class.new(project: project, current_user_sub: "user-sub-123").call

    expect(result).to be_failure
    expect(result.error).to include("Another provisioning job")
  end

  it "returns failure for non-oidc auth configs" do
    auth_config.update!(auth_type: "saml")

    result = described_class.new(project: project, current_user_sub: "user-sub-123").call

    expect(result).to be_failure
    expect(result.error).to include("OIDC")
  end

  it "surfaces the rotated secret in-memory when the reveal cache write fails" do
    stub_keycloak_regenerate_client_secret(uuid: "uuid-123", secret: "new-client-secret")
    allow(AuthConfigs::SecretRevealCache).to receive(:write).and_raise("cache boom")
    allow(Rails.logger).to receive(:error)

    result = described_class.new(project: project, current_user_sub: "user-sub-123").call

    expect(result).to be_success
    expect(result.data[:cache_failed]).to be(true)
    expect(result.data[:reveal_payload].dig("secrets", "client_secret", "value")).to eq("new-client-secret")
    expect(AuthConfigs::SecretRevealCache.read(project).fetch("secrets")).to eq({})
    audit = project.audit_logs.order(:id).last
    expect(audit.action).to eq("auth_config.secret_regenerated")
    expect(audit.details["cache_failed"]).to be(true)
  end
end
