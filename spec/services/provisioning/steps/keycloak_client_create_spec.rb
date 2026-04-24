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
end
