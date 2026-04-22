FactoryBot.define do
  factory :project_permission do
    org_membership
    project
    role { "read" }

    trait :write do
      role { "write" }
    end

    trait :read do
      role { "read" }
    end
  end
end
