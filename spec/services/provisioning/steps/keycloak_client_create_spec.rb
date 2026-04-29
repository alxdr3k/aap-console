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

      it "returns true using a positional client_id call" do
        stub_keycloak_get_clients(client_id: auth_config.keycloak_client_id,
                                  clients: [ { "id" => auth_config.keycloak_client_uuid,
                                               "clientId" => auth_config.keycloak_client_id } ])
        expect(build_step(result_snapshot: snap).already_completed?).to be(true)
      end
    end

    context "when the Keycloak client is gone (NotFoundError)" do
      let!(:auth_config) { create(:project_auth_config, :oidc, project: project) }
      let(:snap) { { "keycloak_client_uuid" => auth_config.keycloak_client_uuid } }

      it "returns false so the create step runs again" do
        stub_keycloak_get_clients(client_id: auth_config.keycloak_client_id, clients: [])
        expect(build_step(result_snapshot: snap).already_completed?).to be(false)
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
