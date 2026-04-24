module Provisioning
  module Steps
    class ConfigServerApply < BaseStep
      LITELLM_PARAMS = %i[models guardrails s3_retention_days].freeze

      def execute
        if skip_for_update?
          return { skipped: true, reason: "no LiteLLM params in update operation" }
        end

        client = ConfigServerClient.new
        org = project.organization

        previous_version_id = project.config_versions
                                     .order(created_at: :desc)
                                     .first&.version_id

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

        { version_id: version_id, previous_version_id: previous_version_id, applied: true }
      end

      def rollback
        snapshot = step_record.result_snapshot
        return unless snapshot&.dig("applied")

        client = ConfigServerClient.new
        org = project.organization

        if step_record.provisioning_job.operation == "update" &&
           (prev_version = snapshot["previous_version_id"])
          client.revert_changes(
            org: org.slug,
            project: project.slug,
            service: "litellm",
            target_version: prev_version,
            idempotency_key: "config-revert-#{step_record.id}"
          )
          record_rollback_version(prev_version)
        else
          client.delete_changes(
            org: org.slug,
            project: project.slug,
            service: "litellm",
            idempotency_key: "config-delete-#{step_record.id}"
          )
        end
      rescue BaseClient::ApiError
        Rails.logger.error "Config server rollback failed for project #{project.id}"
      end

      def already_completed?
        step_record.result_snapshot&.dig("applied") == true
      end

      private

      def skip_for_update?
        step_record.provisioning_job.operation == "update" &&
          LITELLM_PARAMS.none? { |k| params.key?(k) }
      end

      def build_litellm_config
        if step_record.provisioning_job.operation == "update"
          build_merged_litellm_config
        else
          build_full_litellm_config
        end
      end

      def build_full_litellm_config
        {
          models: params[:models] || [],
          guardrails: params[:guardrails] || [],
          s3_path: "#{project.organization.slug}/#{project.slug}/",
          s3_retention_days: params[:s3_retention_days] || 90,
          app_id: project.app_id
        }
      end

      def build_merged_litellm_config
        base = project.config_versions.order(created_at: :desc).first&.snapshot&.transform_keys(&:to_sym) || {}
        merged = base.merge(
          s3_path: "#{project.organization.slug}/#{project.slug}/",
          app_id: project.app_id
        )
        merged[:models] = params[:models] if params.key?(:models)
        merged[:guardrails] = params[:guardrails] if params.key?(:guardrails)
        merged[:s3_retention_days] = params[:s3_retention_days] if params.key?(:s3_retention_days)
        merged
      end

      def build_secrets
        secrets = {}

        langfuse_step = step_record.provisioning_job
                                   .provisioning_steps
                                   .find_by(name: "langfuse_project_create", status: :completed)

        if langfuse_step&.result_snapshot
          if (pk = langfuse_step.result_snapshot["public_key"])
            secrets["LANGFUSE_PUBLIC_KEY"] = pk
          end
          if (sk = params[:langfuse_secret_key])
            secrets["LANGFUSE_SECRET_KEY"] = sk
          end
        end

        secrets
      end

      def record_rollback_version(reverted_to_version_id)
        prior = project.config_versions.find_by(version_id: reverted_to_version_id)
        ConfigVersion.create!(
          project: project,
          provisioning_job: step_record.provisioning_job,
          version_id: reverted_to_version_id,
          change_type: "rollback",
          change_summary: "Rolled back to #{reverted_to_version_id}",
          changed_by_sub: "system",
          snapshot: prior&.snapshot || {}
        )
      end

      def build_change_summary
        changes = []
        changes << "models: #{params[:models].join(', ')}" if params[:models]
        changes << "guardrails updated" if params[:guardrails]
        changes << "s3_retention_days: #{params[:s3_retention_days]}" if params[:s3_retention_days]
        changes.join("; ")
      end
    end
  end
end
