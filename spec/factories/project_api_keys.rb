FactoryBot.define do
  factory :project_api_key do
    project
    sequence(:name) { |n| "api-key-#{n}" }
    token_digest { Digest::SHA256.hexdigest("pak-#{SecureRandom.alphanumeric(32)}") }
    token_prefix { "pak-#{SecureRandom.alphanumeric(4)}" }

    trait :revoked do
      revoked_at { Time.current }
    end
  end
end
