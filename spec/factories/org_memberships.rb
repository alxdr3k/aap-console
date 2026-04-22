FactoryBot.define do
  factory :org_membership do
    organization
    sequence(:user_sub) { |n| "user-sub-#{n}" }
    role { "read" }
    invited_at { Time.current }

    trait :admin do
      role { "admin" }
    end

    trait :write do
      role { "write" }
    end

    trait :read do
      role { "read" }
    end

    trait :joined do
      joined_at { Time.current }
    end
  end
end
