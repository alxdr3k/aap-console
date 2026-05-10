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
    stub_keycloak_regenerate_client_secret(uuid: "uuid-123", secret: "new-client-secret",
                                           client_id: "aap-acme-chatbot-oidc")

    result = described_class.new(project: project, current_user_sub: "user-sub-123").call

    expect(result).to be_success
    expect(result.data[:cache_failed]).to be(false)
    expect(result.data[:reveal_payload].dig("secrets", "client_secret", "value")).to eq("new-client-secret")
    # Secret must NOT be written to the shared reveal cache (one-time reveal contract).
    expect(AuthConfigs::SecretRevealCache.read(project).dig("secrets", "client_secret")).to be_nil
    audit = project.audit_logs.order(:id).last
    expect(audit.action).to eq("auth_config.secret_regenerated")
  end

  it "audits and refuses without rotation when pre-fetch identity diverges" do
    # Stale UUID resolves to a different aap-prefixed client. The POST
    # to /client-secret must NOT fire — no foreign client gets rotated.
    stub_keycloak_get_client_by_uuid(uuid: "uuid-123", client_id: "aap-some-other-client")

    result = described_class.new(project: project, current_user_sub: "user-sub-123").call

    expect(result).to be_failure
    expect(result.error).to include("identity mismatch")
    expect(result.error).not_to include("이미 회전")
    expect(WebMock).not_to have_requested(:post, %r{/clients/uuid-123/client-secret})

    audit = project.audit_logs.where(action: "auth_config.keycloak_client_diverged").last
    expect(audit).to be_present
    expect(audit.details["divergence_stage"]).to eq("pre_fetch")
    expect(audit.details["secret_rotated"]).to be(false)
    expect(audit.details["detection_phase"]).to eq("secret_regenerate")
  end

  it "audits a post-fetch divergence as a foreign-client rotation event" do
    # Sequence: pre-check matches expected, POST returns secret for the
    # expected client, then post-revalidation reveals the record was
    # swapped to a different aap-prefixed client. The POST already rotated
    # whichever client was present, so operators must treat the foreign
    # client's secret as compromised and rotate it again.
    stub_keycloak_token
    stub_request(:get, "#{KeycloakMock::BASE}/clients/uuid-123").to_return(
      {
        status: 200,
        body: { id: "uuid-123", clientId: "aap-acme-chatbot-oidc" }.to_json,
        headers: { "Content-Type" => "application/json" }
      },
      {
        status: 200,
        body: { id: "uuid-123", clientId: "aap-some-other-client" }.to_json,
        headers: { "Content-Type" => "application/json" }
      }
    )
    stub_request(:post, "#{KeycloakMock::BASE}/clients/uuid-123/client-secret").to_return(
      status: 200,
      body: { type: "secret", value: "rotated-secret" }.to_json,
      headers: { "Content-Type" => "application/json" }
    )

    result = described_class.new(project: project, current_user_sub: "user-sub-123").call

    expect(result).to be_failure
    expect(result.error).to include("이미 회전")

    audit = project.audit_logs.where(action: "auth_config.keycloak_client_diverged").last
    expect(audit).to be_present
    expect(audit.details["divergence_stage"]).to eq("post_fetch")
    expect(audit.details["secret_rotated"]).to be(true)
    expect(audit.details["detection_phase"]).to eq("secret_regenerate")
    expect(audit.details["live_client_id"]).to eq("aap-some-other-client")
  end

  it "drops a remediation audit on the affected project when the foreign client is known to us" do
    # The accidentally-rotated client is owned by another project in our
    # system. The rotation incident must surface in that project's audit
    # trail too, otherwise an operator who only inspects the affected
    # project would never learn its secret was rotated.
    affected_org = create(:organization)
    affected_project = create(:project, :active, organization: affected_org)
    affected_auth_config = create(:project_auth_config, :oidc,
                                  project: affected_project,
                                  keycloak_client_id: "aap-some-other-client",
                                  keycloak_client_uuid: "uuid-other")

    stub_keycloak_token
    stub_request(:get, "#{KeycloakMock::BASE}/clients/uuid-123").to_return(
      {
        status: 200,
        body: { id: "uuid-123", clientId: "aap-acme-chatbot-oidc" }.to_json,
        headers: { "Content-Type" => "application/json" }
      },
      {
        status: 200,
        body: { id: "uuid-123", clientId: "aap-some-other-client" }.to_json,
        headers: { "Content-Type" => "application/json" }
      }
    )
    stub_request(:post, "#{KeycloakMock::BASE}/clients/uuid-123/client-secret").to_return(
      status: 200,
      body: { type: "secret", value: "rotated-secret" }.to_json,
      headers: { "Content-Type" => "application/json" }
    )

    described_class.new(project: project, current_user_sub: "user-sub-123").call

    affected_audit = affected_project.audit_logs.where(
      action: "auth_config.keycloak_client_secret_unintentionally_rotated"
    ).last
    expect(affected_audit).to be_present
    expect(affected_audit.details["triggering_project_id"]).to eq(project.id)
    expect(affected_audit.details["live_client_id"]).to eq("aap-some-other-client")
    expect(affected_audit.details["action_required"]).to eq("rotate_client_secret")
    expect(affected_audit.resource_id).to eq(affected_auth_config.id.to_s)
  end

  it "wraps malformed verify-GET responses as RotationVerifyError so the audit signal is preserved" do
    # Faraday::ParsingError is not a BaseClient::ApiError, so without
    # broadening the rescue the malformed body would bypass the
    # secret_rotated audit and surface as an unhandled 500.
    stub_keycloak_token
    stub_request(:get, "#{KeycloakMock::BASE}/clients/uuid-123").to_return(
      {
        status: 200,
        body: { id: "uuid-123", clientId: "aap-acme-chatbot-oidc" }.to_json,
        headers: { "Content-Type" => "application/json" }
      },
      {
        status: 200,
        body: "not-json-at-all",
        headers: { "Content-Type" => "application/json" }
      }
    )
    stub_request(:post, "#{KeycloakMock::BASE}/clients/uuid-123/client-secret").to_return(
      status: 200,
      body: { type: "secret", value: "rotated-secret" }.to_json,
      headers: { "Content-Type" => "application/json" }
    )

    result = described_class.new(project: project, current_user_sub: "user-sub-123").call

    expect(result).to be_failure
    expect(result.error).to include("검증에 실패")

    audit = project.audit_logs.where(action: "auth_config.keycloak_client_diverged").last
    expect(audit).to be_present
    expect(audit.details["secret_rotated"]).to be(true)
    expect(audit.details["post_verify_failed"]).to be(true)
  end

  it "audits a post-rotation verify failure as secret_rotated even when the verify GET errors" do
    # Sequence: pre-check matches, POST rotates and returns the new secret,
    # then the post-fetch GET fails with a non-IdentityMismatch ApiError
    # (timeout / 5xx). Without RotationVerifyError, this would surface as
    # a generic "재발급 실패" message even though Keycloak already applied
    # the rotation, leaving operators unable to detect the orphaned change.
    stub_keycloak_token
    stub_request(:get, "#{KeycloakMock::BASE}/clients/uuid-123").to_return(
      {
        status: 200,
        body: { id: "uuid-123", clientId: "aap-acme-chatbot-oidc" }.to_json,
        headers: { "Content-Type" => "application/json" }
      },
      { status: 500, body: "" }
    )
    stub_request(:post, "#{KeycloakMock::BASE}/clients/uuid-123/client-secret").to_return(
      status: 200,
      body: { type: "secret", value: "rotated-secret" }.to_json,
      headers: { "Content-Type" => "application/json" }
    )

    result = described_class.new(project: project, current_user_sub: "user-sub-123").call

    expect(result).to be_failure
    expect(result.error).to include("검증에 실패")

    audit = project.audit_logs.where(action: "auth_config.keycloak_client_diverged").last
    expect(audit).to be_present
    expect(audit.details["secret_rotated"]).to be(true)
    expect(audit.details["post_verify_failed"]).to be(true)
    expect(audit.details["divergence_stage"]).to eq("post_fetch")
    expect(audit.details["cause_class"]).to be_present
  end

  it "audits every ProjectAuthConfig that claims the rotated client_id when duplicates exist" do
    # Until a DB-backed uniqueness invariant is in place, two
    # ProjectAuthConfig rows can locally share keycloak_client_id (e.g.
    # from import or repair). The handler must not silently miss any of
    # them.
    org_a = create(:organization)
    project_a = create(:project, :active, organization: org_a)
    config_a = create(:project_auth_config, :oidc, project: project_a,
                      keycloak_client_id: "aap-some-other-client",
                      keycloak_client_uuid: "uuid-other-a")
    org_b = create(:organization)
    project_b = create(:project, :active, organization: org_b)
    config_b = create(:project_auth_config, :oidc, project: project_b,
                      keycloak_client_id: "aap-some-other-client",
                      keycloak_client_uuid: "uuid-other-b")

    stub_keycloak_token
    stub_request(:get, "#{KeycloakMock::BASE}/clients/uuid-123").to_return(
      {
        status: 200,
        body: { id: "uuid-123", clientId: "aap-acme-chatbot-oidc" }.to_json,
        headers: { "Content-Type" => "application/json" }
      },
      {
        status: 200,
        body: { id: "uuid-123", clientId: "aap-some-other-client" }.to_json,
        headers: { "Content-Type" => "application/json" }
      }
    )
    stub_request(:post, "#{KeycloakMock::BASE}/clients/uuid-123/client-secret").to_return(
      status: 200,
      body: { type: "secret", value: "rotated-secret" }.to_json,
      headers: { "Content-Type" => "application/json" }
    )
    allow(Rails.logger).to receive(:warn)

    described_class.new(project: project, current_user_sub: "user-sub-123").call

    audit_a = project_a.audit_logs.where(
      action: "auth_config.keycloak_client_secret_unintentionally_rotated"
    ).last
    audit_b = project_b.audit_logs.where(
      action: "auth_config.keycloak_client_secret_unintentionally_rotated"
    ).last
    expect(audit_a).to be_present
    expect(audit_b).to be_present
    expect(audit_a.resource_id).to eq(config_a.id.to_s)
    expect(audit_b.resource_id).to eq(config_b.id.to_s)
    expect(audit_a.details["affected_match_count"]).to eq(2)
    expect(Rails.logger).to have_received(:warn).with(/multiple ProjectAuthConfig rows/)
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
    stub_keycloak_regenerate_client_secret(uuid: "uuid-123", secret: "new-client-secret",
                                           client_id: "aap-acme-chatbot-oidc")
    # Simulate stale data from a previous reveal cycle.
    AuthConfigs::SecretRevealCache.write(project, key: "client_secret", label: "Client Secret", value: "old-stale-secret")

    result = described_class.new(project: project, current_user_sub: "user-sub-123").call

    expect(result).to be_success
    expect(result.data[:reveal_payload].dig("secrets", "client_secret", "value")).to eq("new-client-secret")
    # Stale entry must be cleared; fresh secret is never written to shared cache.
    expect(AuthConfigs::SecretRevealCache.read(project).dig("secrets", "client_secret")).to be_nil
  end
end
