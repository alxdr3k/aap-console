require "rails_helper"

RSpec.describe LangfuseClient do
  include LangfuseMock

  let(:client) { described_class.new }

  describe "#create_organization" do
    it "logs in and returns created organization data" do
      stub_langfuse_create_org(name: "Acme Corp", org_id: "lf-org-1")

      result = client.create_organization(name: "Acme Corp")

      expect(result["id"]).to eq("lf-org-1")
      expect(result["name"]).to eq("Acme Corp")
    end
  end

  describe "#update_organization" do
    it "sends the organization id and new name" do
      stub_langfuse_update_org(org_id: "lf-org-1", name: "New Name")

      result = client.update_organization(id: "lf-org-1", name: "New Name")

      expect(result["id"]).to eq("lf-org-1")
      expect(result["name"]).to eq("New Name")
    end
  end

  describe "#create_project" do
    it "returns created project data" do
      stub_langfuse_create_project(name: "acme-chatbot", project_id: "lf-proj-1")

      result = client.create_project(name: "acme-chatbot", org_id: "lf-org-1")

      expect(result["id"]).to eq("lf-proj-1")
      expect(result["name"]).to eq("acme-chatbot")
    end
  end

  describe "#create_api_key" do
    it "returns a key result without exposing the secret in inspect output" do
      stub_langfuse_create_api_key(
        project_id: "lf-proj-1",
        public_key: "pk-lf-test",
        secret_key: "sk-lf-secret"
      )

      result = client.create_api_key(project_id: "lf-proj-1")

      expect(result.public_key).to eq("pk-lf-test")
      expect(result.secret_key).to eq("sk-lf-secret")
      expect(result.inspect).to include("pk-lf-test")
      expect(result.inspect).not_to include("sk-lf-secret")
    end
  end
end
