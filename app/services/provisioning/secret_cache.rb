module Provisioning
  class SecretCache
    TTL = 10.minutes

    def self.write(provisioning_job, key:, label:, value:)
      return if value.blank?

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

    def self.read(provisioning_job)
      payload = Rails.cache.read(cache_key(provisioning_job.id))
      return {} unless payload.is_a?(Hash)
      return {} unless payload["organization_id"] == provisioning_job.project.organization_id
      return {} unless payload["project_id"] == provisioning_job.project_id

      payload.slice("secrets", "expires_at")
    end

    def self.cache_key(provisioning_job_id)
      "provisioning_job_secrets_#{provisioning_job_id}"
    end

    def self.payload_for(provisioning_job, secrets)
      {
        "organization_id" => provisioning_job.project.organization_id,
        "project_id" => provisioning_job.project_id,
        "secrets" => secrets,
        "expires_at" => TTL.from_now.iso8601
      }
    end
  end
end
