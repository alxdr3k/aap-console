class LangfuseClient < BaseClient
  def initialize
    super(base_url: ENV.fetch("LANGFUSE_URL"))
    @service_email = ENV.fetch("LANGFUSE_SERVICE_EMAIL")
    @service_password = ENV.fetch("LANGFUSE_SERVICE_PASSWORD")
    @session_cookie = nil
    @session_mutex = Mutex.new
  end

  # Organization management

  def create_organization(name:)
    response = trpc_call("organizations.create", { name: name })
    response.dig("result", "data")
  end

  def update_organization(id:, name:)
    response = trpc_call("organizations.update", { id: id, name: name })
    response.dig("result", "data")
  end

  def delete_organization(id:)
    trpc_call("organizations.delete", { id: id })
    true
  end

  # Project management

  def create_project(name:, org_id:)
    response = trpc_call("projects.create", { name: name, organizationId: org_id })
    response.dig("result", "data")
  end

  def delete_project(id:)
    trpc_call("projects.delete", { projectId: id })
    true
  end

  # API Key management

  def create_api_key(project_id:)
    response = trpc_call("projectApiKeys.create", { projectId: project_id })
    data = response.dig("result", "data")
    KeyResult.new(
      public_key: data["publicKey"],
      secret_key: data["secretKey"],
      id: data["id"]
    )
  end

  def list_api_keys(project_id:)
    response = trpc_call("projectApiKeys.byProjectId", { projectId: project_id })
    response.dig("result", "data") || []
  end

  def delete_api_key(id:)
    trpc_call("projectApiKeys.delete", { id: id })
    true
  end

  # Immutable value object for API key — prevents accidental logging of secret_key
  KeyResult = Struct.new(:public_key, :secret_key, :id, keyword_init: true) do
    def inspect = "#<LangfuseClient::KeyResult public_key=#{public_key.inspect} id=#{id.inspect}>"
    def to_s = inspect
  end

  private

  def trpc_call(procedure, input = {})
    ensure_session!
    response = post(
      "/api/trpc/#{procedure}",
      body: { json: input },
      headers: cookie_headers
    )
    response.body
  rescue UnauthorizedError
    # Session expired — refresh and retry once
    @session_mutex.synchronize { @session_cookie = nil }
    ensure_session!
    response = post(
      "/api/trpc/#{procedure}",
      body: { json: input },
      headers: cookie_headers
    )
    response.body
  end

  def ensure_session!
    @session_mutex.synchronize do
      login! if @session_cookie.nil?
    end
  end

  def login!
    response = post(
      "/api/auth/callback/credentials",
      body: { email: @service_email, password: @service_password }
    )
    set_cookie = response.env.response_headers["set-cookie"]
    raise UnauthorizedError.new("Langfuse login failed") if set_cookie.nil?

    @session_cookie = set_cookie.split(";").first
  end

  def cookie_headers
    { "Cookie" => @session_cookie }
  end
end
