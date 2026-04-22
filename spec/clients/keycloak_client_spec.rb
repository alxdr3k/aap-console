require "rails_helper"

RSpec.describe KeycloakClient do
  include KeycloakMock

  let(:client) { described_class.new }

  before do
    stub_keycloak_token
  end

  describe "#search_users" do
    it "returns matching users" do
      stub_keycloak_search_users(query: "john", users: [ { "id" => "user-1", "email" => "john@example.com" } ])
      result = client.search_users(query: "john")
      expect(result).to be_an(Array)
      expect(result.first["email"]).to eq("john@example.com")
    end
  end

  describe "#get_user" do
    it "returns user by sub" do
      stub_keycloak_get_user(user_sub: "user-1", user: { "id" => "user-1", "email" => "user@example.com" })
      result = client.get_user(user_sub: "user-1")
      expect(result["email"]).to eq("user@example.com")
    end
  end

  describe "#create_user" do
    it "creates a user by email" do
      stub_keycloak_create_user(email: "new@example.com")
      expect { client.create_user(email: "new@example.com") }.not_to raise_error
    end
  end

  describe "#create_oidc_client" do
    it "creates an OIDC client with aap- prefix" do
      client_id = "aap-acme-chatbot-oidc"
      stub_keycloak_create_client(client_id: client_id)
      stub_keycloak_get_clients(client_id: client_id, clients: [ { "clientId" => client_id, "id" => "uuid-123" } ])
      result = client.create_oidc_client(client_id: client_id, redirect_uris: [ "https://app.example.com/callback" ])
      expect(result["clientId"]).to eq(client_id)
    end

    it "raises ArgumentError if client_id does not start with aap-" do
      expect { client.create_oidc_client(client_id: "bad-client", redirect_uris: []) }
        .to raise_error(ArgumentError, /must start with 'aap-'/)
    end
  end

  describe "#delete_client" do
    it "deletes a client by uuid" do
      stub_keycloak_delete_client(uuid: "uuid-123")
      expect { client.delete_client(uuid: "uuid-123") }.not_to raise_error
    end

    it "raises ArgumentError if uuid is blank" do
      expect { client.delete_client(uuid: "") }.to raise_error(ArgumentError)
    end
  end

  describe "#get_client_secret" do
    it "returns the client secret" do
      stub_keycloak_get_client_secret(uuid: "uuid-123", secret: "my-secret")
      result = client.get_client_secret(uuid: "uuid-123")
      expect(result).to eq("my-secret")
    end
  end

  describe "#regenerate_client_secret" do
    it "regenerates and returns the client secret" do
      stub_keycloak_regenerate_client_secret(uuid: "uuid-123", secret: "new-secret")
      result = client.regenerate_client_secret(uuid: "uuid-123")
      expect(result).to eq("new-secret")
    end
  end
end
