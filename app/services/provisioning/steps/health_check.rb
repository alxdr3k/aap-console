module Provisioning
  module Steps
    class HealthCheck < BaseStep
      def execute
        results = {}
        warnings = []

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

      def check_litellm(warnings)
        # Verify Config Server has the config applied
        client = ConfigServerClient.new
        config = client.get_config(
          org: project.organization.slug,
          project: project.slug,
          service: "litellm"
        )
        { status: "ok", config_present: config.present? }
      rescue BaseClient::ApiError => e
        warnings << "LiteLLM config check failed: #{e.message}"
        { status: "warning", error: e.message }
      end

      def check_langfuse(warnings)
        langfuse_step = step_record.provisioning_job
                                   .provisioning_steps
                                   .find_by(name: "langfuse_project_create", status: :completed)
        return { status: "skipped" } unless langfuse_step&.result_snapshot&.dig("langfuse_project_id")

        { status: "ok", project_id: langfuse_step.result_snapshot["langfuse_project_id"] }
      rescue => e
        warnings << "Langfuse check failed: #{e.message}"
        { status: "warning", error: e.message }
      end
    end
  end
end
