FactoryBot.define do
  factory :organization do
    sequence(:name) { |n| "Organization #{n}" }
    sequence(:slug) { |n| "org-#{n}" }
    description { "Test organization" }
    langfuse_org_id { nil }
  end
end
