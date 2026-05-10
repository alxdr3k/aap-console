module KeycloakMock
  KEYCLOAK_URL = "http://keycloak.test"
  REALM = "aap"
  BASE = "#{KEYCLOAK_URL}/admin/realms/#{REALM}"
  TOKEN_URL = "#{KEYCLOAK_URL}/realms/#{REALM}/protocol/openid-connect/token"

  def stub_keycloak_token
    stub_request(:post, TOKEN_URL)
      .to_return(
        status: 200,
        body: { access_token: "test-access-token", expires_in: 3600 }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  def stub_keycloak_create_client(client_id:, uuid: SecureRandom.uuid)
    stub_keycloak_token
    stub_request(:post, "#{BASE}/clients")
      .to_return(
        status: 201,
        headers: { "Location" => "#{BASE}/clients/#{uuid}" }
      )
    uuid
  end

  def stub_keycloak_get_client_secret(uuid:, secret: "test-client-secret", client_id: "aap-test-client")
    stub_keycloak_get_client_by_uuid(uuid: uuid, client_id: client_id)
    stub_request(:get, "#{BASE}/clients/#{uuid}/client-secret")
      .to_return(
        status: 200,
        body: { type: "secret", value: secret }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
    secret
  end

  def stub_keycloak_get_client_by_uuid(uuid:, client_id: "aap-test-client")
    stub_keycloak_token
    stub_request(:get, "#{BASE}/clients/#{uuid}")
      .to_return(
        status: 200,
        body: { id: uuid, clientId: client_id }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  def stub_keycloak_delete_client(uuid:, client_id: "aap-test-client")
    stub_keycloak_get_client_by_uuid(uuid: uuid, client_id: client_id)
    stub_request(:delete, "#{BASE}/clients/#{uuid}")
      .to_return(status: 204)
  end

  def stub_keycloak_get_clients(client_id:, clients: [])
    stub_keycloak_token
    stub_request(:get, "#{BASE}/clients")
      .with(query: hash_including("clientId" => client_id))
      .to_return(
        status: 200,
        body: clients.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  def stub_keycloak_get_client(uuid:, client: nil, status: 200)
    stub_keycloak_token
    body = if status == 200
             client || { id: uuid, clientId: "aap-test-client" }
    else
             { error: "Not found" }
    end
    stub_request(:get, "#{BASE}/clients/#{uuid}")
      .to_return(
        status: status,
        body: body.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  def stub_keycloak_search_users(query:, users: [])
    stub_keycloak_token
    stub_request(:get, "#{BASE}/users")
      .with(query: hash_including("search" => query))
      .to_return(
        status: 200,
        body: users.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  def stub_keycloak_get_user(user_sub:, user: nil, status: 200)
    stub_keycloak_token
    user ||= { id: user_sub, email: "user@example.com", firstName: "Test", lastName: "User" }
    stub_request(:get, "#{BASE}/users/#{user_sub}")
      .to_return(
        status: status,
        body: status == 200 ? user.to_json : { error: "Not found" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  def stub_keycloak_create_user(email:, user_sub: SecureRandom.uuid)
    stub_keycloak_token
    stub_request(:post, "#{BASE}/users")
      .to_return(
        status: 201,
        headers: { "Location" => "#{BASE}/users/#{user_sub}" }
      )
    user_sub
  end

  def stub_keycloak_delete_user(user_sub:)
    stub_keycloak_token
    stub_request(:delete, "#{BASE}/users/#{user_sub}")
      .to_return(status: 204)
  end

  def stub_keycloak_update_client(uuid:, client_id: "aap-test-client")
    stub_keycloak_get_client_by_uuid(uuid: uuid, client_id: client_id)
    stub_request(:put, "#{BASE}/clients/#{uuid}")
      .to_return(status: 204)
  end

  def stub_keycloak_regenerate_client_secret(uuid:, secret: "new-client-secret", client_id: "aap-test-client")
    stub_keycloak_get_client_by_uuid(uuid: uuid, client_id: client_id)
    stub_request(:post, "#{BASE}/clients/#{uuid}/client-secret")
      .to_return(
        status: 200,
        body: { type: "secret", value: secret }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
    secret
  end
end

RSpec.configure do |config|
  config.include KeycloakMock
end
