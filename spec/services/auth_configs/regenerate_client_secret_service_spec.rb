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

  it "regenerates the client secret and returns it in-memory without caching" do
    stub_keycloak_regenerate_client_secret(uuid: "uuid-123", secret: "new-client-secret")

    result = described_class.new(project: project, current_user_sub: "user-sub-123").call

    expect(result).to be_success
    expect(result.data[:cache_failed]).to be(false)
    expect(result.data[:reveal_payload].dig("secrets", "client_secret", "value")).to eq("new-client-secret")
    # Secret must NOT be written to the shared reveal cache (one-time reveal contract).
    expect(AuthConfigs::SecretRevealCache.read(project).dig("secrets", "client_secret")).to be_nil
    audit = project.audit_logs.order(:id).last
    expect(audit.action).to eq("auth_config.secret_regenerated")
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

  it "clears any stale cache entry from a prior rotation without writing a new one" do
    stub_keycloak_regenerate_client_secret(uuid: "uuid-123", secret: "new-client-secret")
    # Simulate stale data from a previous reveal cycle.
    AuthConfigs::SecretRevealCache.write(project, key: "client_secret", label: "Client Secret", value: "old-stale-secret")

    result = described_class.new(project: project, current_user_sub: "user-sub-123").call

    expect(result).to be_success
    expect(result.data[:reveal_payload].dig("secrets", "client_secret", "value")).to eq("new-client-secret")
    # Stale entry must be cleared; fresh secret is never written to shared cache.
    expect(AuthConfigs::SecretRevealCache.read(project).dig("secrets", "client_secret")).to be_nil
  end
end
