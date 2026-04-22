module Provisioning
  module Steps
    class ConfigServerApply < BaseStep
      def execute
        client = ConfigServerClient.new
        org = project.organization

        config = build_litellm_config
        secrets = build_secrets

        response = client.apply_changes(
          org: org.slug,
          project: project.slug,
          service: "litellm",
          config: config,
          env_vars: {},
          secrets: secrets,
          idempotency_key: "config-apply-#{step_record.id}"
        )

        version_id = response["version"]

        ConfigVersion.create!(
          project: project,
          provisioning_job: step_record.provisioning_job,
          version_id: version_id,
          change_type: step_record.provisioning_job.operation,
          change_summary: build_change_summary,
          changed_by_sub: params[:current_user_sub] || "system",
          snapshot: config
        )

        { version_id: version_id, applied: true }
      end

      def rollback
        return unless step_record.result_snapshot&.dig("applied")

        client = ConfigServerClient.new
        org = project.organization

        client.delete_changes(
          org: org.slug,
          project: project.slug,
          service: "litellm",
          idempotency_key: "config-delete-#{step_record.id}"
        )
      rescue BaseClient::ApiError
        # Best-effort rollback; log and continue
        Rails.logger.error "Config server rollback failed for project #{project.id}"
      end

      def already_completed?
        step_record.result_snapshot&.dig("applied") == true
      end

      private

      def build_litellm_config
        {
          models: params[:models] || [],
          guardrails: params[:guardrails] || [],
          s3_path: "#{project.organization.slug}/#{project.slug}/",
          s3_retention_days: params[:s3_retention_days] || 90,
          app_id: project.app_id
        }
      end

      def build_secrets
        secrets = {}

        # Forward Langfuse SDK keys if available from langfuse_project_create step
        langfuse_step = step_record.provisioning_job
                                   .provisioning_steps
                                   .find_by(name: "langfuse_project_create", status: :completed)

        if langfuse_step&.result_snapshot
          if (pk = langfuse_step.result_snapshot["public_key"])
            secrets["LANGFUSE_PUBLIC_KEY"] = pk
          end
          # secret_key is passed via job params, not stored in snapshot
          if (sk = params[:langfuse_secret_key])
            secrets["LANGFUSE_SECRET_KEY"] = sk
          end
        end

        secrets
      end

      def build_change_summary
        changes = []
        changes << "models: #{(params[:models] || []).join(', ')}" if params[:models]
        changes << "guardrails updated" if params[:guardrails]
        changes << "s3_retention_days: #{params[:s3_retention_days]}" if params[:s3_retention_days]
        changes.join("; ")
      end
    end
  end
end
