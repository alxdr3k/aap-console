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

  describe "#get_client_secret" do
    it "returns the client secret" do
      stub_keycloak_get_client_secret(uuid: "uuid-123", secret: "my-secret",
                                      client_id: "aap-expected-client")
      result = client.get_client_secret(uuid: "uuid-123",
                                        expected_client_id: "aap-expected-client")
      expect(result).to eq("my-secret")
    end

    it "raises ArgumentError when expected_client_id is missing" do
      expect {
        client.get_client_secret(uuid: "uuid-123", expected_client_id: nil)
      }.to raise_error(ArgumentError, /expected_client_id/)
    end

    it "raises IdentityMismatchError when expected_client_id does not match the live client" do
      stub_keycloak_get_client_secret(uuid: "uuid-123", secret: "my-secret",
                                      client_id: "aap-some-other-client")

      expect {
        client.get_client_secret(uuid: "uuid-123", expected_client_id: "aap-expected-client")
      }.to raise_error(KeycloakClient::IdentityMismatchError) do |error|
        expect(error.uuid).to eq("uuid-123")
        expect(error.expected_client_id).to eq("aap-expected-client")
        expect(error.live_client_id).to eq("aap-some-other-client")
      end
    end

    it "does not call /client-secret when the identity check fails" do
      stub_keycloak_get_client_secret(uuid: "uuid-123", secret: "my-secret",
                                      client_id: "aap-some-other-client")

      begin
        client.get_client_secret(uuid: "uuid-123", expected_client_id: "aap-expected-client")
      rescue KeycloakClient::IdentityMismatchError
        # expected
      end

      expect(WebMock).not_to have_requested(:get, %r{/clients/uuid-123/client-secret})
    end

    it "raises IdentityMismatchError when the post-fetch identity revalidation diverges" do
      # Sequence: precheck GET matches, /client-secret returns the value,
      # then a second GET (post-fetch revalidation) reveals the record was
      # swapped to a different aap-prefixed client. The fetched value must
      # not be returned to the caller — otherwise it could be cached/exposed.
      stub_keycloak_token
      stub_request(:get, "#{KeycloakMock::BASE}/clients/uuid-late-swap").to_return(
        {
          status: 200,
          body: { id: "uuid-late-swap", clientId: "aap-expected-client" }.to_json,
          headers: { "Content-Type" => "application/json" }
        },
        {
          status: 200,
          body: { id: "uuid-late-swap", clientId: "aap-some-other-client" }.to_json,
          headers: { "Content-Type" => "application/json" }
        }
      )
      stub_request(:get, "#{KeycloakMock::BASE}/clients/uuid-late-swap/client-secret").to_return(
        status: 200,
        body: { type: "secret", value: "the-secret" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      expect {
        client.get_client_secret(uuid: "uuid-late-swap", expected_client_id: "aap-expected-client")
      }.to raise_error(KeycloakClient::IdentityMismatchError) do |error|
        expect(error.live_client_id).to eq("aap-some-other-client")
      end
    end
  end

  describe "#regenerate_client_secret" do
    it "regenerates and returns the client secret" do
      stub_keycloak_regenerate_client_secret(uuid: "uuid-123", secret: "new-secret",
                                             client_id: "aap-expected-client")
      result = client.regenerate_client_secret(uuid: "uuid-123",
                                               expected_client_id: "aap-expected-client")
      expect(result).to eq("new-secret")
    end

    it "raises ArgumentError when expected_client_id is missing" do
      expect {
        client.regenerate_client_secret(uuid: "uuid-123", expected_client_id: nil)
      }.to raise_error(ArgumentError, /expected_client_id/)
    end

    it "raises IdentityMismatchError when the live clientId does not match" do
      stub_keycloak_regenerate_client_secret(uuid: "uuid-123", secret: "new-secret",
                                             client_id: "aap-some-other-client")

      expect {
        client.regenerate_client_secret(uuid: "uuid-123",
                                        expected_client_id: "aap-expected-client")
      }.to raise_error(KeycloakClient::IdentityMismatchError) do |error|
        expect(error.live_client_id).to eq("aap-some-other-client")
        expect(error.stage).to eq("pre_fetch")
      end
    end

    it "raises IdentityMismatchError when post-rotation revalidation diverges" do
      stub_keycloak_token
      stub_request(:get, "#{KeycloakMock::BASE}/clients/uuid-late-swap").to_return(
        {
          status: 200,
          body: { id: "uuid-late-swap", clientId: "aap-expected-client" }.to_json,
          headers: { "Content-Type" => "application/json" }
        },
        {
          status: 200,
          body: { id: "uuid-late-swap", clientId: "aap-some-other-client" }.to_json,
          headers: { "Content-Type" => "application/json" }
        }
      )
      stub_request(:post, "#{KeycloakMock::BASE}/clients/uuid-late-swap/client-secret").to_return(
        status: 200,
        body: { type: "secret", value: "rotated-secret" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      expect {
        client.regenerate_client_secret(uuid: "uuid-late-swap",
                                        expected_client_id: "aap-expected-client")
      }.to raise_error(KeycloakClient::IdentityMismatchError) do |error|
        expect(error.live_client_id).to eq("aap-some-other-client")
        expect(error.stage).to eq("post_fetch")
      end
    end
  end

  describe "#update_client" do
    it "raises ArgumentError when expected_client_id is missing" do
      expect {
        client.update_client(uuid: "uuid-123", attributes: {}, expected_client_id: nil)
      }.to raise_error(ArgumentError, /expected_client_id/)
    end

    it "raises IdentityMismatchError when the live clientId does not match" do
      stub_keycloak_get_client_by_uuid(uuid: "uuid-123", client_id: "aap-some-other-client")

      expect {
        client.update_client(uuid: "uuid-123", attributes: { redirectUris: [] },
                             expected_client_id: "aap-expected-client")
      }.to raise_error(KeycloakClient::IdentityMismatchError) do |error|
        expect(error.live_client_id).to eq("aap-some-other-client")
      end

      expect(WebMock).not_to have_requested(:put, %r{/clients/uuid-123\b})
    end

    it "issues PUT when the identity matches" do
      stub_keycloak_update_client(uuid: "uuid-123", client_id: "aap-expected-client")

      expect {
        client.update_client(uuid: "uuid-123", attributes: { redirectUris: [ "https://x" ] },
                             expected_client_id: "aap-expected-client")
      }.not_to raise_error
    end
  end

  describe "#delete_client" do
    it "raises ArgumentError when uuid is blank" do
      expect {
        client.delete_client(uuid: "", expected_client_id: "aap-expected-client")
      }.to raise_error(ArgumentError, /uuid/)
    end

    it "raises ArgumentError when expected_client_id is missing" do
      expect {
        client.delete_client(uuid: "uuid-123", expected_client_id: nil)
      }.to raise_error(ArgumentError, /expected_client_id/)
    end

    it "raises IdentityMismatchError when the live clientId does not match" do
      stub_keycloak_get_client_by_uuid(uuid: "uuid-123", client_id: "aap-some-other-client")

      expect {
        client.delete_client(uuid: "uuid-123", expected_client_id: "aap-expected-client")
      }.to raise_error(KeycloakClient::IdentityMismatchError) do |error|
        expect(error.live_client_id).to eq("aap-some-other-client")
      end

      expect(WebMock).not_to have_requested(:delete, %r{/clients/uuid-123\b})
    end

    it "issues DELETE when the identity matches" do
      stub_keycloak_delete_client(uuid: "uuid-123", client_id: "aap-expected-client")

      expect {
        client.delete_client(uuid: "uuid-123", expected_client_id: "aap-expected-client")
      }.not_to raise_error
    end
  end
end
