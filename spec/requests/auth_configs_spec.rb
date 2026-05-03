require "rails_helper"

RSpec.describe "AuthConfigs", type: :request do
  let(:user_sub) { "user-sub-123" }
  let!(:org) { create(:organization) }
  let!(:project) { create(:project, :active, organization: org) }
  let(:html_headers) { { "ACCEPT" => "text/html" } }
  let(:wildcard_headers) { { "ACCEPT" => "*/*" } }
  let(:json_headers) { { "ACCEPT" => "application/json" } }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }

  before do
    login_as(user_sub)
    allow(Rails).to receive(:cache).and_return(cache)
  end

  describe "GET /organizations/:org_slug/projects/:slug/auth_config" do
    before do
      membership = create(:org_membership, organization: org, user_sub: user_sub, role: "read")
      create(:project_permission, org_membership: membership, project: project, role: "read")
      create(:project_auth_config, project: project, auth_type: "oidc")
    end

    it "returns 200 with auth config" do
      get "/organizations/#{org.slug}/projects/#{project.slug}/auth_config"
      expect(response).to have_http_status(:ok)
    end

    it "returns 403 for member without project permission" do
      other_project = create(:project, :active, organization: org)
      create(:project_auth_config, project: other_project, auth_type: "oidc")
      get "/organizations/#{org.slug}/projects/#{other_project.slug}/auth_config"
      expect(response).to have_http_status(:forbidden)
    end

    it "renders the browser auth config page for project readers" do
      config = project.project_auth_config
      create(:project_api_key, project: project, name: "staging-ci")
      config.update!(
        redirect_uris: [ "https://app.example.com/callback" ],
        post_logout_redirect_uris: [ "https://app.example.com" ]
      )

      get "/organizations/#{org.slug}/projects/#{project.slug}/auth_config", headers: html_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("인증 설정")
      expect(response.body).to include(config.keycloak_client_id)
      expect(response.body).to include("https://app.example.com/callback")
      expect(response.body).to include("read only")
      expect(response.body).to include("Project API Keys")
      expect(response.body).to include("staging-ci")
    end

    context "when auth_type is saml and client is provisioned" do
      before do
        stub_const("ENV", ENV.to_h.merge("KEYCLOAK_URL" => "https://keycloak.example.com", "KEYCLOAK_REALM" => "aap"))
        project.project_auth_config.update!(
          auth_type: "saml",
          keycloak_client_id: "aap-#{org.slug}-#{project.slug}-saml"
        )
      end

      it "renders SAML panel with SP Entity ID and IdP metadata URL copy button" do
        get "/organizations/#{org.slug}/projects/#{project.slug}/auth_config", headers: html_headers

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("SAML 설정")
        expect(response.body).to include("SP Entity ID")
        expect(response.body).to include("aap-#{org.slug}-#{project.slug}-saml")
        expect(response.body).to include("IdP 메타데이터 URL")
        expect(response.body).to include("https://keycloak.example.com/realms/aap/protocol/saml/descriptor")
        expect(response.body).not_to include("AUTH-6A 예정")
        expect(response.body).not_to include("Client Secret 재발급")
      end
    end

    context "when auth_type is saml and keycloak_client_uuid is absent (unprovisioned)" do
      before do
        project.project_auth_config.update!(
          auth_type: "saml",
          keycloak_client_uuid: nil
        )
      end

      it "renders SAML panel with provisioning pending message instead of URL" do
        get "/organizations/#{org.slug}/projects/#{project.slug}/auth_config", headers: html_headers

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("SAML 설정")
        expect(response.body).to include("프로비저닝이 완료되면")
        expect(response.body).not_to include("IdP 메타데이터 URL")
      end
    end

    context "when auth_type is oauth (reader)" do
      before { project.project_auth_config.update!(auth_type: "oauth") }

      it "renders OAuth panel with public client info and read-only redirect URIs" do
        project.project_auth_config.update!(redirect_uris: [ "https://app.example.com/callback" ])

        get "/organizations/#{org.slug}/projects/#{project.slug}/auth_config", headers: html_headers

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("OAuth / PKCE 설정")
        expect(response.body).to include("Public Client")
        expect(response.body).to include("S256")
        expect(response.body).to include("https://app.example.com/callback")
        expect(response.body).not_to include("준비 중")
        expect(response.body).not_to include("Client Secret 재발급")
      end
    end
  end

  describe "PATCH /organizations/:org_slug/projects/:slug/auth_config" do
    before do
      membership = create(:org_membership, organization: org, user_sub: user_sub, role: "write")
      create(:project_permission, org_membership: membership, project: project, role: "write")
      create(:project_auth_config,
             project: project,
             auth_type: "oidc",
             keycloak_client_id: "aap-acme-chatbot-oidc",
             keycloak_client_uuid: "server-owned-uuid")
    end

    it "ignores client attempts to write server-owned keycloak identifiers" do
      original = project.project_auth_config
      patch "/organizations/#{org.slug}/projects/#{project.slug}/auth_config",
            params: { auth_config: {
              keycloak_client_id: "hacker-value",
              keycloak_client_uuid: "hacker-uuid"
            } },
            headers: wildcard_headers

      expect(response).to have_http_status(:ok)
      original.reload
      expect(original.keycloak_client_id).to eq("aap-acme-chatbot-oidc")
      expect(original.keycloak_client_uuid).to eq("server-owned-uuid")
    end

    it "returns 202 Accepted with provisioning_job_id when redirect_uris change" do
      expect {
        patch "/organizations/#{org.slug}/projects/#{project.slug}/auth_config",
              params: { auth_config: { redirect_uris: [ "https://new.example.com/callback" ] } },
              headers: wildcard_headers
      }.to change(ProvisioningJob, :count).by(1)

      expect(response).to have_http_status(:accepted)
      body = JSON.parse(response.body)
      expect(body["provisioning_job_id"]).to eq(project.provisioning_jobs.order(:id).last.id)
    end

    it "seeds the correct steps for a redirect_uri update" do
      patch "/organizations/#{org.slug}/projects/#{project.slug}/auth_config",
            params: { auth_config: { redirect_uris: [ "https://new.example.com/callback" ] } },
            headers: wildcard_headers

      job = project.provisioning_jobs.order(:id).last
      expect(job.operation).to eq("update")
      expect(job.provisioning_steps.order(:step_order, :id).pluck(:name)).to eq(%w[
        keycloak_client_update
        config_server_apply
        health_check
      ])
    end

    it "normalizes blank URI rows to an explicit empty array so users can clear values" do
      patch "/organizations/#{org.slug}/projects/#{project.slug}/auth_config",
            params: { auth_config: { redirect_uris: [ "" ] } },
            headers: wildcard_headers

      job = project.provisioning_jobs.order(:id).last
      expect(job.input_snapshot["redirect_uris"]).to eq([])
    end

    context "OAuth PKCE redirect URI validation" do
      before do
        project.project_auth_config.update!(
          auth_type: "oauth",
          keycloak_client_id: "aap-#{org.slug}-#{project.slug}-oauth"
        )
      end

      it "accepts HTTPS redirect URIs for OAuth" do
        expect {
          patch "/organizations/#{org.slug}/projects/#{project.slug}/auth_config",
                params: { auth_config: { redirect_uris: [ "https://app.example.com/callback" ] } },
                headers: wildcard_headers
        }.to change(ProvisioningJob, :count).by(1)
        expect(response).to have_http_status(:accepted)
      end

      it "accepts http://localhost redirect URIs for OAuth" do
        expect {
          patch "/organizations/#{org.slug}/projects/#{project.slug}/auth_config",
                params: { auth_config: { redirect_uris: [ "http://localhost:3000/callback" ] } },
                headers: wildcard_headers
        }.to change(ProvisioningJob, :count).by(1)
        expect(response).to have_http_status(:accepted)
      end

      it "rejects http (non-localhost) redirect URIs for OAuth" do
        patch "/organizations/#{org.slug}/projects/#{project.slug}/auth_config",
              params: { auth_config: { redirect_uris: [ "http://app.example.com/callback" ] } },
              headers: wildcard_headers
        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)["errors"]).to include(match(/HTTPS를 사용해야 합니다/))
      end

      it "rejects URIs with no host for OAuth" do
        patch "/organizations/#{org.slug}/projects/#{project.slug}/auth_config",
              params: { auth_config: { redirect_uris: [ "https://" ] } },
              headers: wildcard_headers
        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)["errors"]).to include(match(/유효한 호스트/))
      end

      it "rejects non-http/https localhost schemes for OAuth" do
        patch "/organizations/#{org.slug}/projects/#{project.slug}/auth_config",
              params: { auth_config: { redirect_uris: [ "custom://localhost/callback" ] } },
              headers: wildcard_headers
        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)["errors"]).to include(match(/HTTPS를 사용해야 합니다/))
      end

      it "rejects redirect URIs with fragment for OAuth" do
        patch "/organizations/#{org.slug}/projects/#{project.slug}/auth_config",
              params: { auth_config: { redirect_uris: [ "https://app.example.com/callback#section" ] } },
              headers: wildcard_headers
        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)["errors"]).to include(match(/fragment/))
      end
    end

    it "returns 403 for read-only member" do
      other_project = create(:project, :active, organization: org)
      read_membership = create(:org_membership, organization: org, user_sub: "reader", role: "read")
      create(:project_permission, org_membership: read_membership, project: other_project, role: "read")
      create(:project_auth_config, project: other_project, auth_type: "oidc")
      login_as("reader")
      patch "/organizations/#{org.slug}/projects/#{other_project.slug}/auth_config",
            params: { auth_config: { redirect_uris: [ "https://hack" ] } },
            headers: wildcard_headers
      expect(response).to have_http_status(:forbidden)
    end

    it "redirects browser updates to the provisioning job detail page" do
      patch "/organizations/#{org.slug}/projects/#{project.slug}/auth_config",
            params: { auth_config: { redirect_uris: [ "https://new.example.com/callback" ] } },
            headers: html_headers

      expect(response).to redirect_to(provisioning_job_path(project.provisioning_jobs.order(:id).last))
    end

    it "keeps explicit JSON clients on the JSON contract" do
      patch "/organizations/#{org.slug}/projects/#{project.slug}/auth_config",
            params: { auth_config: { redirect_uris: [ "https://json.example.com/callback" ] } },
            headers: json_headers

      expect(response).to have_http_status(:accepted)
      expect(response.media_type).to eq("application/json")
      expect(response.parsed_body["provisioning_job_id"]).to eq(project.provisioning_jobs.order(:id).last.id)
    end

    it "renders browser errors when another provisioning job is active" do
      create(:provisioning_job, :in_progress, project: project, operation: "update")

      patch "/organizations/#{org.slug}/projects/#{project.slug}/auth_config",
            params: { auth_config: { redirect_uris: [ "https://new.example.com/callback" ] } },
            headers: html_headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Another provisioning job is in progress")
    end
  end

  describe "POST /organizations/:org_slug/projects/:slug/auth_config/regenerate_secret" do
    before do
      membership = create(:org_membership, organization: org, user_sub: user_sub, role: "write")
      create(:project_permission, org_membership: membership, project: project, role: "write")
      create(:project_auth_config,
             project: project,
             auth_type: "oidc",
             keycloak_client_id: "aap-acme-chatbot-oidc",
             keycloak_client_uuid: "server-owned-uuid")
      stub_keycloak_regenerate_client_secret(uuid: "server-owned-uuid", secret: "new-client-secret")
      cache.clear
    end

    it "regenerates the secret and redirects back to the auth config page" do
      post "/organizations/#{org.slug}/projects/#{project.slug}/auth_config/regenerate_secret",
           headers: html_headers

      expect(response).to redirect_to(organization_project_auth_config_path(org.slug, project.slug))
      expect(AuthConfigs::SecretRevealCache.read(project).dig("secrets", "client_secret", "value")).to eq("new-client-secret")
    end

    it "renders the reveal panel with no-store headers after redirect" do
      post "/organizations/#{org.slug}/projects/#{project.slug}/auth_config/regenerate_secret",
           headers: html_headers

      follow_redirect!

      expect(response).to have_http_status(:ok)
      expect(response.headers["Cache-Control"]).to eq("no-store")
      expect(response.body).to include("일회성 인증 정보")
      expect(response.body).to include("10분 TTL")
      expect(response.body).to include("new-client-secret")
    end

    it "returns JSON for explicit JSON clients" do
      post "/organizations/#{org.slug}/projects/#{project.slug}/auth_config/regenerate_secret",
           headers: json_headers

      expect(response).to have_http_status(:created)
      expect(response.media_type).to eq("application/json")
      expect(response.parsed_body.dig("secrets", "client_secret", "value")).to eq("new-client-secret")
    end

    it "changes the reveal confirmation storage key for each regenerated secret" do
      post "/organizations/#{org.slug}/projects/#{project.slug}/auth_config/regenerate_secret",
           headers: html_headers
      follow_redirect!
      first_key = response.body[/data-secret-reveal-storage-key-value="([^"]+)"/, 1]

      post "/organizations/#{org.slug}/projects/#{project.slug}/auth_config/regenerate_secret",
           headers: html_headers
      follow_redirect!
      second_key = response.body[/data-secret-reveal-storage-key-value="([^"]+)"/, 1]

      expect(first_key).to be_present
      expect(second_key).to be_present
      expect(second_key).not_to eq(first_key)
    end
  end
end
