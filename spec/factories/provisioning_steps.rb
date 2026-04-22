FactoryBot.define do
  factory :provisioning_step do
    provisioning_job
    sequence(:name) { |n| "step_#{n}" }
    step_order { 1 }
    status { :pending }
    max_retries { 3 }

    trait :app_registry_register do
      name { "app_registry_register" }
      step_order { 1 }
    end

    trait :keycloak_client_create do
      name { "keycloak_client_create" }
      step_order { 2 }
    end

    trait :langfuse_project_create do
      name { "langfuse_project_create" }
      step_order { 2 }
    end

    trait :config_server_apply do
      name { "config_server_apply" }
      step_order { 3 }
    end

    trait :health_check do
      name { "health_check" }
      step_order { 4 }
    end

    trait :pending do
      status { :pending }
    end

    trait :in_progress do
      status { :in_progress }
      started_at { Time.current }
    end

    trait :completed do
      status { :completed }
      started_at { 5.seconds.ago }
      completed_at { Time.current }
    end

    trait :failed do
      status { :failed }
      started_at { 5.seconds.ago }
      completed_at { Time.current }
      error_message { "Step failed" }
    end
  end
end
