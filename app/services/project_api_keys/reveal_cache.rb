module ProjectApiKeys
  class RevealCache
    TTL = 10.minutes

    class << self
      def write(project, project_api_key:, token:)
        payload = payload_for(project)
        payload["secrets"]["project_api_key"] = {
          "label" => "Project API Key",
          "value" => token,
          "name" => project_api_key.name,
          "token_prefix" => project_api_key.token_prefix
        }
        payload["generated_at"] = Time.current.iso8601(6)
        payload["expires_at"] = TTL.from_now.iso8601(6)

        Rails.cache.write(cache_key(project), payload, expires_in: TTL)
        payload
      end

      def read(project)
        payload = Rails.cache.read(cache_key(project))
        return payload_for(project) unless payload.is_a?(Hash)
        return payload_for(project) unless payload["organization_id"] == project.organization_id
        return payload_for(project) unless payload["project_id"] == project.id

        payload
      end

      def delete(project)
        Rails.cache.delete(cache_key(project))
      end

      private

      def cache_key(project)
        "project-api-key-reveal:#{project.id}"
      end

      def payload_for(project)
        {
          "organization_id" => project.organization_id,
          "project_id" => project.id,
          "secrets" => {}
        }
      end
    end
  end
end
