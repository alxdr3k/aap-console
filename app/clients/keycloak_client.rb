class KeycloakClient < BaseClient
  def initialize
    super(
      base_url: ENV.fetch("KEYCLOAK_URL"),
      timeout: 10,
      open_timeout: 5
    )
    @realm = ENV.fetch("KEYCLOAK_REALM", "aap")
    @client_id = ENV.fetch("KEYCLOAK_CLIENT_ID", "aap-console")
    @client_secret = ENV.fetch("KEYCLOAK_CLIENT_SECRET")
    @token_mutex = Mutex.new
    @access_token = nil
    @token_expires_at = nil
  end

  # User management

  def search_users(query:)
    response = get(users_path, params: { search: query }, headers: auth_headers)
    response.body
  end

  def get_user(user_sub:)
    response = get("#{users_path}/#{CGI.escape(user_sub.to_s)}", headers: auth_headers)
    response.body
  end

  def get_users_by_ids(user_subs:)
    user_subs = Array(user_subs).compact.uniq
    return {} if user_subs.blank?

    pool = Concurrent::FixedThreadPool.new([ user_subs.size, 5 ].min)
    results = Concurrent::Hash.new

    futures = user_subs.map do |sub|
      Concurrent::Future.execute(executor: pool) do
        begin
          user = get_user(user_sub: sub)
          results[sub] = user
        rescue NotFoundError
          # deleted user — skip
        end
      end
    end

    futures.each do |future|
      future.value
      raise future.reason if future.rejected?
    end

    results
  ensure
    pool&.shutdown
  end

  def create_user(email:)
    response = post(users_path, body: { email: email, enabled: true }, headers: auth_headers)
    body = response.body

    return body if body.is_a?(Hash) && body["id"].present?

    location = response.headers["location"] || response.headers["Location"]
    user_sub = location.to_s.split("/").last
    raise ApiError.new("Keycloak create user response missing location", status: response.status, body: body) if user_sub.blank?

    { "id" => user_sub, "email" => email }
  end

  def delete_user(user_sub:)
    delete("#{users_path}/#{CGI.escape(user_sub.to_s)}", headers: auth_headers)
  end

  # Client management (only `aap-` prefixed clients)

  def create_oidc_client(client_id:, redirect_uris:)
    raise ArgumentError, "client_id must start with 'aap-'" unless client_id.start_with?("aap-")

    body = {
      clientId: client_id,
      protocol: "openid-connect",
      publicClient: false,
      serviceAccountsEnabled: true,
      redirectUris: redirect_uris
    }
    post(clients_path, body: body, headers: auth_headers)
    get_client_by_client_id(client_id)
  end

  def create_saml_client(client_id:, attributes: {})
    raise ArgumentError, "client_id must start with 'aap-'" unless client_id.start_with?("aap-")

    body = {
      clientId: client_id,
      protocol: "saml",
      attributes: attributes
    }
    post(clients_path, body: body, headers: auth_headers)
    get_client_by_client_id(client_id)
  end

  def create_oauth_client(client_id:, redirect_uris:)
    raise ArgumentError, "client_id must start with 'aap-'" unless client_id.start_with?("aap-")

    body = {
      clientId: client_id,
      protocol: "openid-connect",
      publicClient: true,
      attributes: { "pkce.code.challenge.method" => "S256" },
      redirectUris: redirect_uris
    }
    post(clients_path, body: body, headers: auth_headers)
    get_client_by_client_id(client_id)
  end

  def get_client_by_client_id(client_id)
    response = get(clients_path, params: { clientId: client_id }, headers: auth_headers)
    clients = response.body
    clients.first || raise(NotFoundError.new("Client not found: #{client_id}"))
  end

  def update_client(uuid:, attributes:)
    raise ArgumentError, "uuid is required" if uuid.blank?

    put("#{clients_path}/#{uuid}", body: attributes, headers: auth_headers)
  end

  def delete_client(uuid:)
    raise ArgumentError, "uuid is required" if uuid.blank?

    delete("#{clients_path}/#{uuid}", headers: auth_headers)
  end

  def get_client_secret(uuid:)
    response = get("#{clients_path}/#{uuid}/client-secret", headers: auth_headers)
    response.body["value"]
  end

  def regenerate_client_secret(uuid:)
    response = post("#{clients_path}/#{uuid}/client-secret", headers: auth_headers)
    response.body["value"]
  end

  def assign_client_scope(client_uuid:, scope_id:)
    put("#{clients_path}/#{client_uuid}/default-client-scopes/#{scope_id}", headers: auth_headers)
  end

  private

  def users_path
    "/admin/realms/#{@realm}/users"
  end

  def clients_path
    "/admin/realms/#{@realm}/clients"
  end

  def token_url
    "#{@base_url}/realms/#{@realm}/protocol/openid-connect/token"
  end

  def auth_headers
    { "Authorization" => "Bearer #{access_token}" }
  end

  def access_token
    @token_mutex.synchronize do
      if @access_token.nil? || token_expired?
        fetch_token
      end
      @access_token
    end
  end

  def token_expired?
    @token_expires_at.nil? || Time.current >= @token_expires_at
  end

  def fetch_token
    response = Faraday.post(token_url, {
      grant_type: "client_credentials",
      client_id: @client_id,
      client_secret: @client_secret
    })

    raise UnauthorizedError.new("Failed to obtain Keycloak token") unless response.success?

    data = JSON.parse(response.body)
    @access_token = data["access_token"]
    @token_expires_at = Time.current + data["expires_in"].to_i.seconds - 30.seconds
  end
end
