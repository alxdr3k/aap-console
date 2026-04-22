require "rails_helper"

RSpec.describe ConfigServerClient do
  include ConfigServerMock

  let(:client) { described_class.new }

  describe "#apply_changes" do
    it "posts changes and returns version info" do
      stub_config_server_apply_changes(version: "v1-abc123")
      result = client.apply_changes(
        org: "acme", project: "chatbot", service: "litellm",
        config: { models: [ "gpt-4" ] },
        idempotency_key: "idem-123"
      )
      expect(result["version"]).to eq("v1-abc123")
    end
  end

  describe "#notify_app_registry" do
    it "sends app registry webhook" do
      stub_config_server_app_registry_webhook
      expect do
        client.notify_app_registry(
          action: "register",
          app_data: { app_id: "app-abc123" },
          idempotency_key: "idem-456"
        )
      end.not_to raise_error
    end
  end

  describe "#get_config" do
    it "retrieves config for org/project/service" do
      stub_config_server_get_config(org: "acme", project: "chatbot", service: "litellm", config: { "models" => [ "gpt-4" ] })
      result = client.get_config(org: "acme", project: "chatbot", service: "litellm")
      expect(result["models"]).to include("gpt-4")
    end
  end
end
