module ConfigServerMock
  CONFIG_SERVER_URL = "http://config-server.test"
  ADMIN_BASE = "#{CONFIG_SERVER_URL}/api/v1/admin"

  def stub_config_server_apply_changes(version: "v-test-#{SecureRandom.hex(4)}")
    stub_request(:post, "#{ADMIN_BASE}/changes")
      .to_return(
        status: 200,
        body: { version: version }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
    version
  end

  def stub_config_server_delete_changes
    stub_request(:delete, /api\/v1\/admin\/changes/)
      .to_return(
        status: 200,
        body: { version: "v-deleted-#{SecureRandom.hex(4)}" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  def stub_config_server_revert_changes(version:)
    stub_request(:post, "#{ADMIN_BASE}/changes/revert")
      .to_return(
        status: 200,
        body: { version: version }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  def stub_config_server_revert_changes_failure(status: 500)
    stub_request(:post, "#{ADMIN_BASE}/changes/revert")
      .to_return(
        status: status,
        body: { error: "internal error" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  def stub_config_server_delete_changes_failure(status: 500)
    stub_request(:delete, /api\/v1\/admin\/changes/)
      .to_return(
        status: status,
        body: { error: "internal error" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  def stub_config_server_app_registry_webhook
    stub_request(:post, "#{ADMIN_BASE}/app-registry/webhook")
      .to_return(
        status: 200,
        body: { success: true }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  def stub_config_server_get_config(org:, project:, service:, config: {})
    stub_request(:get, "#{CONFIG_SERVER_URL}/api/v1/config")
      .with(query: hash_including("org" => org, "project" => project, "service" => service))
      .to_return(
        status: 200,
        body: config.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end
end

RSpec.configure do |config|
  config.include ConfigServerMock
end
