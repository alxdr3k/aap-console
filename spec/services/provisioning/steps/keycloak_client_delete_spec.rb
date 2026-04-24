require "rails_helper"

RSpec.describe Provisioning::Steps::KeycloakClientDelete do
  let(:organization) { create(:organization) }
  let(:project) { create(:project, :active, organization: organization) }
  let(:job) { create(:provisioning_job, :delete, project: project) }

  def build_step
    step_record = create(:provisioning_step, provisioning_job: job,
                         name: "keycloak_client_delete", step_order: 1)
    described_class.new(step_record: step_record, project: project, params: {})
  end

  describe "#already_completed?" do
    context "when there is no auth_config" do
      it "returns true (nothing to delete)" do
        expect(build_step.already_completed?).to be(true)
      end
    end

    context "when auth_type is pak (no Keycloak client to begin with)" do
      let!(:auth_config) { create(:project_auth_config, :pak, project: project) }

      it "returns true" do
        expect(build_step.already_completed?).to be(true)
      end
    end

    context "when the Keycloak client still exists" do
      let!(:auth_config) { create(:project_auth_config, :oidc, project: project) }

      it "returns false so the delete step proceeds" do
        stub_keycloak_get_clients(client_id: auth_config.keycloak_client_id,
                                  clients: [ { "id" => auth_config.keycloak_client_uuid,
                                               "clientId" => auth_config.keycloak_client_id } ])
        expect(build_step.already_completed?).to be(false)
      end
    end

    context "when the Keycloak client is already gone (NotFoundError)" do
      let!(:auth_config) { create(:project_auth_config, :oidc, project: project) }

      it "returns true so the delete step skips" do
        stub_keycloak_get_clients(client_id: auth_config.keycloak_client_id, clients: [])
        expect(build_step.already_completed?).to be(true)
      end
    end
  end
end
