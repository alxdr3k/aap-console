FactoryBot.define do
  factory :provisioning_job do
    project
    operation { "create" }
    status { :pending }

    trait :create do
      operation { "create" }
    end

    trait :update do
      operation { "update" }
    end

    trait :delete do
      operation { "delete" }
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
      started_at { 30.seconds.ago }
      completed_at { Time.current }
    end

    trait :completed_with_warnings do
      status { :completed_with_warnings }
      started_at { 30.seconds.ago }
      completed_at { Time.current }
    end

    trait :failed do
      status { :failed }
      started_at { 30.seconds.ago }
      completed_at { Time.current }
      error_message { "Provisioning failed" }
    end

    trait :retrying do
      status { :retrying }
      started_at { 30.seconds.ago }
    end

    trait :rolling_back do
      status { :rolling_back }
      started_at { 30.seconds.ago }
    end

    trait :rolled_back do
      status { :rolled_back }
      started_at { 30.seconds.ago }
      completed_at { Time.current }
    end

    trait :rollback_failed do
      status { :rollback_failed }
      started_at { 30.seconds.ago }
      completed_at { Time.current }
      error_message { "Rollback failed" }
    end
  end
end
