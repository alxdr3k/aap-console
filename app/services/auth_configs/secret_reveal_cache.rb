module AuthConfigs
  class SecretRevealCache
    TTL = 10.minutes

    class << self
      def write(project, key:, label:, value:)
        payload = read(project)
        payload["secrets"][key.to_s] = {
          "label" => label,
          "value" => value
        }
        payload["generated_at"] ||= Time.current.iso8601(6)
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
        "auth-config-secret:#{project.id}"
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
