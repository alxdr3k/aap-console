module LangfuseMock
  LANGFUSE_URL = "http://langfuse.test"
  TRPC_BASE = "#{LANGFUSE_URL}/api/trpc"
  AUTH_URL = "#{LANGFUSE_URL}/api/auth/callback/credentials"

  def stub_langfuse_login(session_token: "test-session-token")
    stub_request(:post, AUTH_URL)
      .to_return(
        status: 200,
        body: { ok: true }.to_json,
        headers: {
          "Content-Type" => "application/json",
          "Set-Cookie" => "next-auth.session-token=#{session_token}; Path=/; HttpOnly"
        }
      )
    session_token
  end

  def stub_langfuse_create_org(name:, org_id: SecureRandom.uuid, status: 200)
    stub_langfuse_login
    stub_request(:post, "#{TRPC_BASE}/organizations.create")
      .to_return(
        status: status,
        body: status == 200 ? { result: { data: { id: org_id, name: name } } }.to_json : { error: "Internal Server Error" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
    org_id
  end

  def stub_langfuse_delete_org(org_id:)
    stub_langfuse_login
    stub_request(:post, "#{TRPC_BASE}/organizations.delete")
      .to_return(
        status: 200,
        body: { result: { data: { success: true } } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  def stub_langfuse_create_project(name:, project_id: SecureRandom.uuid)
    stub_langfuse_login
    stub_request(:post, "#{TRPC_BASE}/projects.create")
      .to_return(
        status: 200,
        body: { result: { data: { id: project_id, name: name } } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
    project_id
  end

  def stub_langfuse_delete_project(project_id:)
    stub_langfuse_login
    stub_request(:post, "#{TRPC_BASE}/projects.delete")
      .to_return(
        status: 200,
        body: { result: { data: { success: true } } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  def stub_langfuse_create_api_key(project_id:, public_key: "pk-lf-test", secret_key: "sk-lf-test")
    stub_langfuse_login
    stub_request(:post, "#{TRPC_BASE}/projectApiKeys.create")
      .to_return(
        status: 200,
        body: {
          result: {
            data: {
              id: SecureRandom.uuid,
              publicKey: public_key,
              secretKey: secret_key,
              projectId: project_id
            }
          }
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
    { public_key: public_key, secret_key: secret_key }
  end

  def stub_langfuse_delete_api_key(key_id:)
    stub_langfuse_login
    stub_request(:post, "#{TRPC_BASE}/projectApiKeys.delete")
      .to_return(
        status: 200,
        body: { result: { data: { success: true } } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end
end

RSpec.configure do |config|
  config.include LangfuseMock
end
