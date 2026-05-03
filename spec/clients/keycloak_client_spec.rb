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

  describe "#get_users_by_ids" do
    it "skips deleted users" do
      stub_keycloak_get_user(user_sub: "user-1", user: { "id" => "user-1", "email" => "user@example.com" })
      stub_keycloak_get_user(user_sub: "deleted-user", status: 404)

      result = client.get_users_by_ids(user_subs: [ "user-1", "deleted-user" ])

      expect(result.keys).to contain_exactly("user-1")
    end

    it "propagates non-404 lookup errors" do
      stub_keycloak_get_user(user_sub: "user-1", status: 500)

      expect { client.get_users_by_ids(user_subs: [ "user-1" ]) }
        .to raise_error(BaseClient::ServerError)
    end
  end

  describe "#create_user" do
    it "creates a user by email" do
      stub_keycloak_create_user(email: "new@example.com", user_sub: "created-user-sub")
      result = client.create_user(email: "new@example.com")
      expect(result["id"]).to eq("created-user-sub")
      expect(result["email"]).to eq("new@example.com")
    end
  end

  describe "#delete_user" do
    it "deletes a user by sub" do
      stub_keycloak_delete_user(user_sub: "created-user-sub")
      expect { client.delete_user(user_sub: "created-user-sub") }.not_to raise_error
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

  describe "#create_saml_client" do
    it "creates a SAML client with attributes" do
      client_id = "aap-acme-chatbot-saml"
      stub_keycloak_create_client(client_id: client_id)
      stub_keycloak_get_clients(client_id: client_id, clients: [ { "clientId" => client_id, "id" => "uuid-saml" } ])

      result = client.create_saml_client(
        client_id: client_id,
        attributes: { "saml.force.post.binding" => "true" }
      )

      expect(result["id"]).to eq("uuid-saml")
      expect(a_request(:post, "#{KeycloakMock::BASE}/clients").with { |request|
        body = JSON.parse(request.body)
        body["clientId"] == client_id &&
          body["protocol"] == "saml" &&
          body["attributes"] == { "saml.force.post.binding" => "true" }
      }).to have_been_made
    end
  end

  describe "#create_oauth_client" do
    it "creates a public OAuth client with PKCE enabled" do
      client_id = "aap-acme-chatbot-oauth"
      stub_keycloak_create_client(client_id: client_id)
      stub_keycloak_get_clients(client_id: client_id, clients: [ { "clientId" => client_id, "id" => "uuid-oauth" } ])

      result = client.create_oauth_client(
        client_id: client_id,
        redirect_uris: [ "https://app.example.com/callback" ]
      )

      expect(result["id"]).to eq("uuid-oauth")
      expect(a_request(:post, "#{KeycloakMock::BASE}/clients").with { |request|
        body = JSON.parse(request.body)
        body["clientId"] == client_id &&
          body["protocol"] == "openid-connect" &&
          body["publicClient"] == true &&
          body["redirectUris"] == [ "https://app.example.com/callback" ] &&
          body["attributes"] == { "pkce.code.challenge.method" => "S256" }
      }).to have_been_made
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
