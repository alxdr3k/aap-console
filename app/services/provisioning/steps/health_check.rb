module Provisioning
  module Steps
    class HealthCheck < BaseStep
      def execute
        results = {}
        warnings = []

        results[:keycloak] = check_keycloak(warnings)
        results[:litellm] = check_litellm(warnings)
        results[:langfuse] = check_langfuse(warnings)

        if warnings.any?
          step_record.provisioning_job.warnings ||= []
          step_record.provisioning_job.warnings.concat(warnings.map { |w| { step: "health_check", message: w } })
          step_record.provisioning_job.save!
          raise HealthCheckWarning, warnings.join("; ")
        end

        { checks: results, passed: true }
      end

      def rollback
        # Health check has no side effects; no-op.
      end

      def already_completed?
        # Health check is always re-run for freshness.
        false
      end

      private

      HealthCheckWarning = Class.new(StandardError)

      def check_keycloak(warnings)
        auth_config = project.project_auth_config
        client_id = auth_config&.keycloak_client_id
        return { status: "skipped", reason: "no Keycloak-backed auth config" } if client_id.blank?

        client = KeycloakClient.new.get_client_by_client_id(client_id)
        uuid = client["id"]
        expected_uuid = auth_config.keycloak_client_uuid

        if expected_uuid.present? && uuid != expected_uuid
          message = "Keycloak client mismatch: expected #{expected_uuid}, got #{uuid || 'nil'}"
          warnings << message
          return { status: "warning", client_id: client_id, error: message }
        end

        { status: "ok", client_id: client_id, uuid: uuid }
      rescue BaseClient::NotFoundError
        message = "Keycloak client missing: #{client_id}"
        warnings << message
        { status: "warning", client_id: client_id, error: message }
      rescue BaseClient::ApiError => e
        warnings << "Keycloak client check failed: #{e.message}"
        { status: "warning", client_id: client_id, error: e.message }
      end

      def check_litellm(warnings)
        config_step = completed_step("config_server_apply")
        if config_step&.result_snapshot&.dig("skipped") == true
          return { status: "skipped", reason: config_step.result_snapshot["reason"] }
        end

        expected_config = config_step&.result_snapshot&.dig("config_snapshot")
        version_id = config_step&.result_snapshot&.dig("version_id")

        client = ConfigServerClient.new
        config = client.get_config(
          org: project.organization.slug,
          project: project.slug,
          service: "litellm"
        )

        if config.blank?
          warnings << "LiteLLM config missing"
          return { status: "warning", version_id: version_id, error: "config missing" }
        end

        mismatches = config_mismatches(expected_config, config)
        if mismatches.any?
          message = "LiteLLM config mismatch: #{mismatches.join(', ')}"
          warnings << message
          return { status: "warning", version_id: version_id, error: message }
        end

        { status: "ok", config_present: true, version_id: version_id }
      rescue BaseClient::ApiError => e
        warnings << "LiteLLM config check failed: #{e.message}"
        { status: "warning", error: e.message }
      end

      def check_langfuse(warnings)
        langfuse_step = completed_step("langfuse_project_create")
        snapshot = langfuse_step&.result_snapshot
        project_id = snapshot&.dig("langfuse_project_id")
        public_key = snapshot&.dig("public_key")
        return { status: "skipped" } if project_id.blank?

        keys = LangfuseClient.new.list_api_keys(project_id: project_id)
        if public_key.present? && !keys.any? { |key| public_key_for(key) == public_key }
          message = "Langfuse API key missing: #{public_key}"
          warnings << message
          return { status: "warning", project_id: project_id, error: message }
        end

        { status: "ok", project_id: project_id, public_key_present: public_key.present? }
      rescue => e
        warnings << "Langfuse check failed: #{e.message}"
        { status: "warning", error: e.message }
      end

      def completed_step(name)
        step_record.provisioning_job.provisioning_steps.find_by(name: name, status: :completed)
      end

      def config_mismatches(expected_config, actual_config)
        expected = normalize_config(expected_config)
        return [] if expected.blank?

        actual = normalize_config(actual_config)
        actual = actual["config"] if actual["config"].is_a?(Hash)

        expected.filter_map do |key, expected_value|
          actual_value = actual[key]
          next if actual_value == expected_value

          "#{key} expected #{expected_value.inspect}, got #{actual_value.inspect}"
        end
      end

      def normalize_config(value)
        case value
        when Hash
          value.to_h { |key, nested| [ key.to_s, normalize_config(nested) ] }
        when Array
          value.map { |nested| normalize_config(nested) }
        else
          value
        end
      end

      def public_key_for(key)
        key["publicKey"] || key["public_key"]
      end
    end
  end
end
