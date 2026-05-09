class KeycloakClient < BaseClient
  class IdentityMismatchError < ApiError
    attr_reader :uuid, :expected_client_id, :live_client_id, :stage

    # `stage` distinguishes a pre-mutation/pre-fetch identity check from a
    # post-fetch revalidation that fires after a /client-secret read or a
    # /client-secret POST has already returned a value. Operators use the
    # stage to decide whether the secret cache is merely empty or whether a
    # foreign client's value may have been observed in-process and rotation
    # is required.
    def initialize(uuid:, expected_client_id:, live_client_id:, stage: "pre_fetch")
      @uuid = uuid
      @expected_client_id = expected_client_id
      @live_client_id = live_client_id
      @stage = stage
      super(
        "Refusing Keycloak operation (stage=#{stage}): live clientId=#{live_client_id.inspect} " \
        "differs from expected #{expected_client_id.inspect} for uuid=#{uuid.inspect}"
      )
    end
  end

  # Raised when a /client-secret POST already committed a rotation but the
  # post-rotation identity verification could not complete (timeout, 5xx,
  # malformed body, etc.). Distinct from IdentityMismatchError — the
  # identity is unknown rather than known-foreign — but operators must
  # treat the secret as rotated and reconcile manually.
  class RotationVerifyError < ApiError
    attr_reader :uuid, :expected_client_id, :secret_rotated, :cause_class, :cause_message

    def initialize(uuid:, expected_client_id:, cause:, secret_rotated: true)
      @uuid = uuid
      @expected_client_id = expected_client_id
      @secret_rotated = secret_rotated
      @cause_class = cause.class.name
      @cause_message = cause.message
      super(
        "Post-rotation verification failed (secret_rotated=#{secret_rotated}) for " \
        "uuid=#{uuid.inspect} expected_client_id=#{expected_client_id.inspect}: " \
        "#{@cause_class}: #{@cause_message}"
      )
    end
  end

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

  # Direct UUID lookup. Use this whenever the snapshot already holds the
  # Keycloak UUID — it bypasses the list endpoint so the result is bound to
  # the exact client that produced the snapshot.
  def get_client(uuid:)
    raise ArgumentError, "uuid is required" if uuid.blank?

    response = get("#{clients_path}/#{uuid}", headers: auth_headers)
    response.body
  end

  def update_client(uuid:, attributes:, expected_client_id:)
    raise ArgumentError, "uuid is required" if uuid.blank?
    raise ArgumentError, "expected_client_id is required" if expected_client_id.blank?

    assert_client_identity!(uuid, expected_client_id)
    put("#{clients_path}/#{uuid}", body: attributes, headers: auth_headers)
  end

  def delete_client(uuid:, expected_client_id:)
    raise ArgumentError, "uuid is required" if uuid.blank?
    raise ArgumentError, "expected_client_id is required" if expected_client_id.blank?

    assert_client_identity!(uuid, expected_client_id)
    delete("#{clients_path}/#{uuid}", headers: auth_headers)
  end

  # `expected_client_id` is required: a stale UUID may resolve to another
  # aap-prefixed client, so the prefix-only invariant is not sufficient for
  # secret reads. Callers must pass the project-owned client_id so the
  # returned value can be bound to the expected identity.
  def get_client_secret(uuid:, expected_client_id:)
    raise ArgumentError, "uuid is required" if uuid.blank?
    raise ArgumentError, "expected_client_id is required" if expected_client_id.blank?

    assert_client_identity!(uuid, expected_client_id)

    response = get("#{clients_path}/#{uuid}/client-secret", headers: auth_headers)
    secret_value = response.body["value"]

    # Post-fetch revalidation is best-effort detection, not a security
    # boundary. The three GETs are independent, so a foreign-client window
    # that opens during /client-secret and closes again before this check
    # remains undetectable. It still catches drift that persists past the
    # secret read; operators that observe a post_fetch mismatch must treat
    # the read value as compromised and rotate via regenerate_client_secret.
    assert_client_identity!(uuid, expected_client_id, stage: "post_fetch")

    secret_value
  end

  def regenerate_client_secret(uuid:, expected_client_id:)
    raise ArgumentError, "uuid is required" if uuid.blank?
    raise ArgumentError, "expected_client_id is required" if expected_client_id.blank?

    assert_client_identity!(uuid, expected_client_id)

    response = post("#{clients_path}/#{uuid}/client-secret", headers: auth_headers)
    secret_value = response.body["value"]

    # Post-rotation revalidation: if the record at this UUID was swapped to
    # another aap-prefixed client between the precheck and the POST, the
    # rotated secret belongs to that foreign client and must not be returned
    # to the caller. Best-effort, same race-window caveat as get_client_secret.
    # Wrap every non-IdentityMismatch failure (timeout, 5xx, malformed JSON,
    # connection drop) so the caller always learns the POST already rotated
    # whichever client was present at this UUID — leaving the verification
    # error untyped would bypass the secret_rotated audit signal.
    begin
      assert_client_identity!(uuid, expected_client_id, stage: "post_fetch")
    rescue IdentityMismatchError
      raise
    rescue StandardError => verify_error
      raise RotationVerifyError.new(uuid: uuid, expected_client_id: expected_client_id,
                                    cause: verify_error, secret_rotated: true)
    end

    secret_value
  end

  def assign_client_scope(client_uuid:, scope_id:, expected_client_id:)
    raise ArgumentError, "client_uuid is required" if client_uuid.blank?
    raise ArgumentError, "expected_client_id is required" if expected_client_id.blank?

    assert_client_identity!(client_uuid, expected_client_id)
    put("#{clients_path}/#{client_uuid}/default-client-scopes/#{scope_id}", headers: auth_headers)
  end

  private

  def assert_client_identity!(uuid, expected_client_id, stage: "pre_fetch")
    client = get_client_by_uuid(uuid)
    live_client_id = client.is_a?(Hash) ? client["clientId"].to_s : ""
    unless live_client_id.start_with?("aap-")
      raise ApiError.new("Refusing to operate on non-aap client #{uuid}")
    end
    if live_client_id != expected_client_id
      raise IdentityMismatchError.new(
        uuid: uuid,
        expected_client_id: expected_client_id,
        live_client_id: live_client_id,
        stage: stage
      )
    end
  end

  def get_client_by_uuid(uuid)
    response = get("#{clients_path}/#{uuid}", headers: auth_headers)
    response.body
  end

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
