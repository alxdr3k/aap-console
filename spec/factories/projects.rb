FactoryBot.define do
  factory :project do
    organization
    sequence(:name) { |n| "Project #{n}" }
    sequence(:slug) { |n| "project-#{n}" }
    description { "Test project" }
    app_id { "app-#{SecureRandom.alphanumeric(12)}" }
    status { :provisioning }

    trait :provisioning do
      status { :provisioning }
    end

    trait :active do
      status { :active }
    end

    trait :update_pending do
      status { :update_pending }
    end

    trait :deleting do
      status { :deleting }
    end

    trait :deleted do
      status { :deleted }
    end

    trait :provision_failed do
      status { :provision_failed }
    end
  end
end
