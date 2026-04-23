module Provisioning
  # Seeds provisioning_steps for a given ProvisioningJob based on its operation.
  # Matches the step plan documented in docs/HLD.md §5.6.
  #
  # Called from Projects::{Create,Update,Destroy}Service inside the same
  # transaction as the job creation so the job and its steps are always
  # in sync before Orchestrator runs.
  class StepSeeder
    class UnknownOperationError < StandardError; end

    DEFAULT_MAX_RETRIES = {
      "app_registry_register"   => 5,
      "app_registry_deregister" => 5,
      "keycloak_client_create"  => 3,
      "keycloak_client_update"  => 3,
      "keycloak_client_delete"  => 3,
      "langfuse_project_create" => 3,
      "langfuse_project_delete" => 3,
      "config_server_apply"     => 3,
      "config_server_delete"    => 3,
      "db_cleanup"              => 3,
      "health_check"            => 2
    }.freeze

    PLANS = {
      "create" => [
        [ "app_registry_register",   1 ],
        [ "keycloak_client_create",  2 ],
        [ "langfuse_project_create", 2 ],
        [ "config_server_apply",     3 ],
        [ "health_check",            4 ]
      ],
      "update" => [
        [ "keycloak_client_update",  1 ],
        [ "config_server_apply",     2 ],
        [ "health_check",            3 ]
      ],
      "delete" => [
        [ "config_server_delete",    1 ],
        [ "keycloak_client_delete",  1 ],
        [ "langfuse_project_delete", 1 ],
        [ "app_registry_deregister", 2 ],
        [ "db_cleanup",              3 ]
      ]
    }.freeze

    def self.call!(job)
      plan = PLANS[job.operation]
      raise UnknownOperationError, "No step plan for operation=#{job.operation.inspect}" if plan.nil?

      plan.each do |name, order|
        step = job.provisioning_steps.find_or_initialize_by(name: name)
        next if step.persisted?

        step.step_order = order
        step.status = :pending
        step.max_retries = DEFAULT_MAX_RETRIES.fetch(name, 3)
        step.save!
      end

      job.provisioning_steps.reload
    end
  end
end
