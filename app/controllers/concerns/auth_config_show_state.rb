module AuthConfigShowState
  extend ActiveSupport::Concern

  private

  def prepare_auth_config_show!(form_values: nil, reveal_payload: nil, pak_reveal_payload: nil)
    base_values = {
      redirect_uris: @auth_config&.redirect_uris,
      post_logout_redirect_uris: @auth_config&.post_logout_redirect_uris
    }
    values = base_values.merge(form_values || {})

    if @auth_config&.auth_type == "saml" && @auth_config.keycloak_client_uuid.present?
      @saml_idp_metadata_url = saml_idp_metadata_url
    end

    @errors ||= []
    @can_write_project = current_authorization.can?(:write_project, @project)
    @active_provisioning_job = @project.provisioning_jobs
                                       .where(status: ProvisioningJob::ACTIVE_STATUSES)
                                       .order(created_at: :desc)
                                       .first
    @redirect_uris = form_rows_for_auth_config(values[:redirect_uris])
    @post_logout_redirect_uris = form_rows_for_auth_config(values[:post_logout_redirect_uris])

    @secret_payload = if reveal_payload && @can_write_project
                        reveal_payload
    elsif @can_write_project
                        AuthConfigs::SecretRevealCache.read(@project)
    else
                        {}
    end
    @secret_entries = @secret_payload.fetch("secrets", {})
    @secret_reveal_storage_key = [
      "auth-config-secret",
      @project.id,
      @secret_payload["generated_at"].presence || "current"
    ].join(":")

    @project_api_keys = @project.project_api_keys.order(created_at: :desc)
    @project_api_key_reveal_payload = if pak_reveal_payload && @can_write_project
                                        pak_reveal_payload
    elsif @can_write_project
                                        ProjectApiKeys::RevealCache.read(@project)
    else
                                        {}
    end
    @project_api_key_reveal = @project_api_key_reveal_payload.dig("secrets", "project_api_key") || {}
    @project_api_key_reveal_storage_key = [
      "project-api-key",
      @project.id,
      @project_api_key_reveal_payload["generated_at"].presence || "current"
    ].join(":")

    @last_secret_regenerated_at = @project.audit_logs
                                          .where(action: "auth_config.secret_regenerated")
                                          .order(created_at: :desc)
                                          .pick(:created_at)
  end

  def form_rows_for_auth_config(values)
    rows = normalize_auth_config_uri_values(values)
    rows.presence || [ "" ]
  end

  def normalize_auth_config_uri_values(values)
    Array(values).map(&:to_s).map(&:strip).reject(&:blank?)
  end

  def disable_secret_response_cache!
    response.headers["Cache-Control"] = "no-store"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"
  end

  def saml_idp_metadata_url
    base = ENV.fetch("KEYCLOAK_URL", "")
    realm = ENV.fetch("KEYCLOAK_REALM", "aap")
    "#{base}/realms/#{realm}/protocol/saml/descriptor"
  end
end
