module Provisioning
  class SecretCache
    TTL = 10.minutes

    class << self
      def write(provisioning_job, key:, label:, value:)
        return if value.blank?

        # Serialize concurrent writes from parallel steps that share the same
        # provisioning_job cache key. Without this, a read-merge-write race can
        # silently drop a successfully minted secret from a sibling step.
        provisioning_job.with_lock do
          existing = Rails.cache.read(cache_key(provisioning_job.id))
          existing_secrets = existing["secrets"] if existing.is_a?(Hash) && existing["secrets"].is_a?(Hash)
          secrets = existing_secrets&.dup || {}
          secrets[key.to_s] = {
            "label" => label,
            "value" => value
          }

          Rails.cache.write(
            cache_key(provisioning_job.id),
            payload_for(provisioning_job, secrets),
            expires_in: TTL
          )
        end
      end

      def read(provisioning_job)
        payload = Rails.cache.read(cache_key(provisioning_job.id))
        return {} unless payload.is_a?(Hash)
        return {} unless payload["organization_id"] == provisioning_job.project.organization_id
        return {} unless payload["project_id"] == provisioning_job.project_id

        payload.slice("secrets", "expires_at")
      end

      def delete(provisioning_job_id)
        Rails.cache.delete(cache_key(provisioning_job_id))
      end

      private

      def cache_key(provisioning_job_id)
        "provisioning_job_secrets_#{provisioning_job_id}"
      end

      def payload_for(provisioning_job, secrets)
        {
          "organization_id" => provisioning_job.project.organization_id,
          "project_id" => provisioning_job.project_id,
          "secrets" => secrets,
          "expires_at" => TTL.from_now.iso8601
        }
      end
    end
  end
end
