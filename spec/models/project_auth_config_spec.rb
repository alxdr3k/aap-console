require "rails_helper"

RSpec.describe ProjectAuthConfig, type: :model do
  describe "validations" do
    it "requires auth_type" do
      record = ProjectAuthConfig.new(auth_type: nil)
      record.valid?
      expect(record.errors[:auth_type]).to include("can't be blank")
    end

    it "rejects unknown auth_type" do
      record = ProjectAuthConfig.new(auth_type: "magic")
      record.valid?
      expect(record.errors[:auth_type]).to include("is not included in the list")
    end
  end

  describe "keycloak_client_id assignment on create" do
    let(:organization) { create(:organization, slug: "acme") }
    let(:project)      { create(:project, organization: organization, slug: "chatbot") }

    %w[oidc saml oauth].each do |auth_type|
      it "fills aap-{org}-{project}-#{auth_type} when blank" do
        record = project.create_project_auth_config!(auth_type: auth_type)
        expect(record.keycloak_client_id).to eq("aap-acme-chatbot-#{auth_type}")
      end
    end

    it "preserves an explicit keycloak_client_id" do
      record = project.create_project_auth_config!(
        auth_type: "oidc",
        keycloak_client_id: "aap-custom-id"
      )
      expect(record.keycloak_client_id).to eq("aap-custom-id")
    end

    it "leaves keycloak_client_id null for PAK-only auth" do
      record = project.create_project_auth_config!(auth_type: "pak")
      expect(record.keycloak_client_id).to be_nil
    end
  end
end
