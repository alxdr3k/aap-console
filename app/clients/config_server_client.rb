class ConfigServerClient < BaseClient
  def initialize
    super(
      base_url: ENV.fetch("CONFIG_SERVER_URL"),
      timeout: 30,
      open_timeout: 5
    )
    @api_key = ENV.fetch("CONFIG_SERVER_API_KEY")
  end

  def apply_changes(org:, project:, service:, config: {}, env_vars: {}, secrets: {}, idempotency_key:)
    response = post(
      "/api/v1/admin/changes",
      body: {
        org: org,
        project: project,
        service: service,
        config: config,
        env_vars: env_vars,
        secrets: secrets
      },
      headers: auth_headers.merge("X-Idempotency-Key" => idempotency_key)
    )
    response.body
  end

  def delete_changes(org:, project:, service:, idempotency_key:)
    path = "/api/v1/admin/changes?#{URI.encode_www_form(org: org, project: project, service: service)}"
    response = delete(
      path,
      headers: auth_headers.merge("X-Idempotency-Key" => idempotency_key)
    )
    response.body
  end

  def revert_changes(org:, project:, service:, target_version:, idempotency_key:)
    response = post(
      "/api/v1/admin/changes/revert",
      body: { org: org, project: project, service: service, targetVersion: target_version },
      headers: auth_headers.merge("X-Idempotency-Key" => idempotency_key)
    )
    response.body
  end

  def notify_app_registry(action:, app_data:, idempotency_key:)
    response = post(
      "/api/v1/admin/app-registry/webhook",
      body: { action: action, app: app_data },
      headers: auth_headers.merge("X-Idempotency-Key" => idempotency_key)
    )
    response.body
  end

  def get_config(org:, project:, service:)
    response = get(
      "/api/v1/config",
      params: { org: org, project: project, service: service },
      headers: auth_headers
    )
    response.body
  end

  def get_secrets_metadata(org:, project:, service:)
    response = get(
      "/api/v1/secrets/metadata",
      params: { org: org, project: project, service: service },
      headers: auth_headers
    )
    response.body
  end

  def get_history(org:, project:, service:)
    response = get(
      "/api/v1/history",
      params: { org: org, project: project, service: service },
      headers: auth_headers
    )
    response.body
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@api_key}" }
  end
end
