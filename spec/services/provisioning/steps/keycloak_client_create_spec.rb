require "rails_helper"

RSpec.describe Provisioning::Steps::KeycloakClientCreate do
  let(:organization) { create(:organization) }
  let(:project) { create(:project, :provisioning, organization: organization) }
  let(:job) { create(:provisioning_job, :create, project: project) }

  def build_step(result_snapshot: nil)
    step_record = create(:provisioning_step, :keycloak_client_create,
                         provisioning_job: job, result_snapshot: result_snapshot)
    described_class.new(step_record: step_record, project: project, params: {})
  end

  describe "#already_completed?" do
    context "when snapshot has no keycloak_client_uuid yet" do
      let!(:auth_config) { create(:project_auth_config, :oidc, project: project) }

      it "returns false (step has not created a client)" do
        expect(build_step(result_snapshot: nil).already_completed?).to be(false)
      end
    end

    context "when auth_config is missing" do
      it "returns false" do
        snap = { "keycloak_client_uuid" => "uuid-1" }
        expect(build_step(result_snapshot: snap).already_completed?).to be(false)
      end
    end

    context "when the Keycloak client still exists" do
      let!(:auth_config) { create(:project_auth_config, :oidc, project: project) }
      let(:snap) { { "keycloak_client_uuid" => auth_config.keycloak_client_uuid } }

      it "returns true via a direct UUID lookup that matches the snapshot" do
        stub_keycloak_get_client(uuid: auth_config.keycloak_client_uuid,
                                 client: { "id" => auth_config.keycloak_client_uuid,
                                           "clientId" => auth_config.keycloak_client_id })
        expect(build_step(result_snapshot: snap).already_completed?).to be(true)
      end
    end

    context "when the Keycloak client is gone (NotFoundError)" do
      let!(:auth_config) { create(:project_auth_config, :oidc, project: project) }
      let(:snap) { { "keycloak_client_uuid" => auth_config.keycloak_client_uuid } }

      it "returns false so the create step runs again" do
        stub_keycloak_get_client(uuid: auth_config.keycloak_client_uuid, status: 404)
        expect(build_step(result_snapshot: snap).already_completed?).to be(false)
      end
    end

    context "when the snapshot UUID is stale (client recreated under same client_id)" do
      let!(:auth_config) { create(:project_auth_config, :oidc, project: project) }
      let(:snap) { { "keycloak_client_uuid" => "uuid-snapshot" } }

      it "returns false because the stale UUID no longer resolves" do
        # Direct UUID GET returns 404 because the snapshot UUID has been removed
        # (a new client with the same clientId now lives under a different UUID).
        stub_keycloak_get_client(uuid: "uuid-snapshot", status: 404)
        expect(build_step(result_snapshot: snap).already_completed?).to be(false)
      end
    end

    context "when the live clientId differs from the snapshot's auth config client_id" do
      let!(:auth_config) { create(:project_auth_config, :oidc, project: project) }
      let(:snap) { { "keycloak_client_uuid" => auth_config.keycloak_client_uuid } }

      it "treats the UUID match as authoritative, logs, and writes a divergence audit" do
        stub_keycloak_get_client(uuid: auth_config.keycloak_client_uuid,
                                 client: { "id" => auth_config.keycloak_client_uuid,
                                           "clientId" => "aap-some-other-client" })
        expect(Rails.logger).to receive(:warn).with(/identity diverges/)
        expect {
          expect(build_step(result_snapshot: snap).already_completed?).to be(true)
        }.to change { AuditLog.where(action: "auth_config.keycloak_client_diverged").count }.by(1)
        audit = AuditLog.where(action: "auth_config.keycloak_client_diverged").last
        expect(audit.details["live_client_id"]).to eq("aap-some-other-client")
        expect(audit.details["expected_client_id"]).to eq(auth_config.keycloak_client_id)
      end
    end

    context "when the live client representation omits clientId" do
      let!(:auth_config) { create(:project_auth_config, :oidc, project: project) }
      let(:snap) { { "keycloak_client_uuid" => auth_config.keycloak_client_uuid } }

      it "still treats the UUID match as authoritative without logging a divergence" do
        stub_keycloak_get_client(uuid: auth_config.keycloak_client_uuid,
                                 client: { "id" => auth_config.keycloak_client_uuid })
        expect(build_step(result_snapshot: snap).already_completed?).to be(true)
      end
    end

    context "when the live representation omits id entirely (schema drift)" do
      let!(:auth_config) { create(:project_auth_config, :oidc, project: project) }
      let(:snap) { { "keycloak_client_uuid" => auth_config.keycloak_client_uuid } }

      it "still treats the UUID-targeted 200 as authoritative completion" do
        stub_keycloak_get_client(uuid: auth_config.keycloak_client_uuid,
                                 client: { "clientId" => auth_config.keycloak_client_id })
        expect(build_step(result_snapshot: snap).already_completed?).to be(true)
      end
    end
  end

  describe "#execute side-effect snapshot atomicity" do
    let!(:auth_config) do
      create(:project_auth_config, :oidc, project: project,
             keycloak_client_id: "aap-#{organization.slug}-#{project.slug}-oidc",
             keycloak_client_uuid: nil)
    end

    it "persists the keycloak_client_uuid snapshot before the local DB write" do
      uuid = stub_keycloak_create_client(client_id: auth_config.keycloak_client_id)
      stub_keycloak_get_clients(client_id: auth_config.keycloak_client_id,
                                clients: [ { "id" => uuid, "clientId" => auth_config.keycloak_client_id } ])

      step_record = create(:provisioning_step, :keycloak_client_create, provisioning_job: job)
      step = described_class.new(step_record: step_record, project: project, params: {})

      # Force the local mirror to fail; snapshot must already exist on the step.
      allow(auth_config).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(auth_config))
      allow(project).to receive(:project_auth_config).and_return(auth_config)

      expect { step.execute }.to raise_error(ActiveRecord::RecordInvalid)
      expect(step_record.reload.result_snapshot["keycloak_client_uuid"]).to eq(uuid)
    end

    it "writes the OIDC client secret only to the reveal cache" do
      cache = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(cache)

      uuid = stub_keycloak_create_client(client_id: auth_config.keycloak_client_id)
      stub_keycloak_get_clients(client_id: auth_config.keycloak_client_id,
                                clients: [ { "id" => uuid, "clientId" => auth_config.keycloak_client_id } ])
      stub_keycloak_get_client_secret(uuid: uuid, secret: "oidc-secret")

      step_record = create(:provisioning_step, :keycloak_client_create, provisioning_job: job)
      step = described_class.new(step_record: step_record, project: project, params: {})

      result = step.execute
      reveal = Provisioning::SecretCache.read(job)

      expect(result).to include(
        keycloak_client_uuid: uuid,
        keycloak_client_id: auth_config.keycloak_client_id
      )
      expect(result.to_json).not_to include("oidc-secret")
      expect(step_record.reload.result_snapshot.to_json).not_to include("oidc-secret")
      expect(reveal.dig("secrets", "client_secret", "value")).to eq("oidc-secret")
    end

    it "refreshes the reveal cache when the Keycloak step is skipped on retry" do
      cache = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(cache)

      uuid = "uuid-existing"
      auth_config.update!(keycloak_client_uuid: uuid)
      stub_keycloak_get_client(uuid: uuid,
                               client: { "id" => uuid, "clientId" => auth_config.keycloak_client_id })
      stub_keycloak_get_client_secret(uuid: uuid, secret: "oidc-secret",
                                      client_id: auth_config.keycloak_client_id)

      step_record = create(
        :provisioning_step,
        :keycloak_client_create,
        provisioning_job: job,
        result_snapshot: {
          "keycloak_client_uuid" => uuid,
          "keycloak_client_id" => auth_config.keycloak_client_id
        }
      )

      runner = Provisioning::StepRunner.new(step: step_record, provisioning_job: job, params: {})
      result = runner.execute

      expect(result[:status]).to eq(:completed)
      expect(step_record.reload).to be_skipped
      expect(Provisioning::SecretCache.read(job).dig("secrets", "client_secret", "value")).to eq("oidc-secret")
    end

    it "uses the persisted snapshot UUID when the auth config mirror is still missing on skip" do
      cache = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(cache)

      uuid = "uuid-from-snapshot"
      auth_config.update!(keycloak_client_uuid: nil)
      stub_keycloak_get_client(uuid: uuid,
                               client: { "id" => uuid, "clientId" => auth_config.keycloak_client_id })
      stub_keycloak_get_client_secret(uuid: uuid, secret: "oidc-secret",
                                      client_id: auth_config.keycloak_client_id)

      step_record = create(
        :provisioning_step,
        :keycloak_client_create,
        provisioning_job: job,
        result_snapshot: {
          "keycloak_client_uuid" => uuid,
          "keycloak_client_id" => auth_config.keycloak_client_id
        }
      )

      runner = Provisioning::StepRunner.new(step: step_record, provisioning_job: job, params: {})
      result = runner.execute

      expect(result[:status]).to eq(:completed)
      expect(step_record.reload).to be_skipped
      expect(Provisioning::SecretCache.read(job).dig("secrets", "client_secret", "value")).to eq("oidc-secret")
    end

    it "skips the secret cache refresh when the live client identity diverges from the snapshot" do
      cache = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(cache)
      allow(Rails.logger).to receive(:warn)

      uuid = "uuid-divergent"
      auth_config.update!(keycloak_client_uuid: uuid)
      stub_keycloak_get_client(uuid: uuid,
                               client: { "id" => uuid, "clientId" => "aap-some-other-client" })

      step_record = create(
        :provisioning_step,
        :keycloak_client_create,
        provisioning_job: job,
        result_snapshot: {
          "keycloak_client_uuid" => uuid,
          "keycloak_client_id" => auth_config.keycloak_client_id
        }
      )

      runner = Provisioning::StepRunner.new(step: step_record, provisioning_job: job, params: {})
      result = runner.execute

      expect(result[:status]).to eq(:completed)
      expect(step_record.reload).to be_skipped
      # Identity divergence must NOT mint a wrong client's secret into the cache;
      # any stale entry should be cleared instead.
      expect(Provisioning::SecretCache.read(job)).to eq({})
      expect(WebMock).not_to have_requested(:get, %r{/clients/#{uuid}/client-secret})
      # Divergence is treated as completed (not retried) to avoid unconditionally
      # POSTing a duplicate client or hard-failing on 409. An audit event is
      # created so operators can investigate the mismatch manually.
      audit = AuditLog.where(action: "auth_config.keycloak_client_diverged").last
      expect(audit).to be_present
      expect(audit.details["expected_client_id"]).to eq(auth_config.keycloak_client_id)
    end

    it "does not fail provisioning when secret caching cannot fetch the client secret" do
      cache = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(cache)

      uuid = stub_keycloak_create_client(client_id: auth_config.keycloak_client_id)
      stub_keycloak_get_clients(client_id: auth_config.keycloak_client_id,
                                clients: [ { "id" => uuid, "clientId" => auth_config.keycloak_client_id } ])

      keycloak = instance_double(KeycloakClient)
      allow(KeycloakClient).to receive(:new).and_return(keycloak)
      allow(keycloak).to receive(:create_oidc_client).and_return({ "id" => uuid })
      allow(keycloak).to receive(:get_client_secret).and_raise(BaseClient::TimeoutError.new("Request timed out"))

      step_record = create(:provisioning_step, :keycloak_client_create, provisioning_job: job)
      step = described_class.new(step_record: step_record, project: project, params: {})

      expect(Rails.logger).to receive(:warn).with(include("skipped secret cache"))

      result = step.execute

      expect(result).to include(
        keycloak_client_uuid: uuid,
        keycloak_client_id: auth_config.keycloak_client_id
      )
      expect(auth_config.reload.keycloak_client_uuid).to eq(uuid)
      expect(Provisioning::SecretCache.read(job)).to eq({})
    end

    it "clears a stale cached secret before attempting to fetch a replacement" do
      cache = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(cache)

      Provisioning::SecretCache.write(
        job,
        key: "client_secret",
        label: "Client Secret",
        value: "stale-secret"
      )

      uuid = stub_keycloak_create_client(client_id: auth_config.keycloak_client_id)
      stub_keycloak_get_clients(client_id: auth_config.keycloak_client_id,
                                clients: [ { "id" => uuid, "clientId" => auth_config.keycloak_client_id } ])

      keycloak = instance_double(KeycloakClient)
      allow(KeycloakClient).to receive(:new).and_return(keycloak)
      allow(keycloak).to receive(:create_oidc_client).and_return({ "id" => uuid })
      allow(keycloak).to receive(:get_client_secret).and_raise(BaseClient::TimeoutError.new("Request timed out"))
      allow(Rails.logger).to receive(:warn)

      step_record = create(:provisioning_step, :keycloak_client_create, provisioning_job: job)
      step = described_class.new(step_record: step_record, project: project, params: {})

      step.execute

      expect(Provisioning::SecretCache.read(job)).to eq({})
    end
  end

  describe "#execute auth type dispatch" do
    it "creates a SAML client with supplied SAML attributes" do
      auth_config = create(:project_auth_config, :saml, project: project,
                           keycloak_client_id: "aap-#{organization.slug}-#{project.slug}-saml",
                           keycloak_client_uuid: nil)
      keycloak = instance_double(KeycloakClient)
      allow(KeycloakClient).to receive(:new).and_return(keycloak)
      expect(keycloak).to receive(:create_saml_client).with(
        client_id: auth_config.keycloak_client_id,
        attributes: { "saml.force.post.binding" => "true" }
      ).and_return({ "id" => "uuid-saml" })

      step_record = create(:provisioning_step, :keycloak_client_create, provisioning_job: job)
      step = described_class.new(
        step_record: step_record,
        project: project,
        params: { saml_attributes: { "saml.force.post.binding" => "true" } }
      )

      expect(step.execute).to include(
        keycloak_client_uuid: "uuid-saml",
        keycloak_client_id: auth_config.keycloak_client_id
      )
      expect(auth_config.reload.keycloak_client_uuid).to eq("uuid-saml")
    end

    it "creates an OAuth client with redirect URIs" do
      auth_config = create(:project_auth_config, :oauth, project: project,
                           keycloak_client_id: "aap-#{organization.slug}-#{project.slug}-oauth",
                           keycloak_client_uuid: nil)
      keycloak = instance_double(KeycloakClient)
      allow(KeycloakClient).to receive(:new).and_return(keycloak)
      expect(keycloak).to receive(:create_oauth_client).with(
        client_id: auth_config.keycloak_client_id,
        redirect_uris: [ "https://app.example.com/callback" ]
      ).and_return({ "id" => "uuid-oauth" })

      step_record = create(:provisioning_step, :keycloak_client_create, provisioning_job: job)
      step = described_class.new(
        step_record: step_record,
        project: project,
        params: { redirect_uris: [ "https://app.example.com/callback" ] }
      )

      expect(step.execute).to include(
        keycloak_client_uuid: "uuid-oauth",
        keycloak_client_id: auth_config.keycloak_client_id
      )
      expect(auth_config.reload.keycloak_client_uuid).to eq("uuid-oauth")
    end
  end
end
