module ProjectApiKeys
  class RevealCache
    TTL = 10.minutes

    class << self
      def write(project, project_api_key:, token:)
        payload = reveal_payload(project, project_api_key: project_api_key, token: token)
        payload if Rails.cache.write(cache_key(project), payload, expires_in: TTL)
      end

      def read(project)
        payload = Rails.cache.read(cache_key(project))
        return empty_payload(project) unless valid_payload?(project, payload)

        payload
      end

      def reveal_payload(project, project_api_key:, token:)
        payload = empty_payload(project)
        payload["secrets"]["project_api_key"] = {
          "project_api_key_id" => project_api_key.id,
          "label" => "Project API Key",
          "value" => token,
          "name" => project_api_key.name,
          "token_prefix" => project_api_key.token_prefix
        }
        payload["generated_at"] = Time.current.iso8601(6)
        payload["expires_at"] = TTL.from_now.iso8601(6)
        payload
      end

      def delete(project)
        Rails.cache.delete(cache_key(project))
      end

      def delete_if_matches(project, project_api_key_id:)
        payload = read(project)
        revealed_key_id = payload.dig("secrets", "project_api_key", "project_api_key_id")
        delete(project) if revealed_key_id.to_i == project_api_key_id.to_i
      end

      private

      def cache_key(project)
        "project-api-key-reveal:#{project.id}"
      end

      def empty_payload(project)
        {
          "organization_id" => project.organization_id,
          "project_id" => project.id,
          "secrets" => {}
        }
      end

      def valid_payload?(project, payload)
        payload.is_a?(Hash) &&
          payload["organization_id"] == project.organization_id &&
          payload["project_id"] == project.id
      end
    end
  end
end
