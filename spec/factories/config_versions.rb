FactoryBot.define do
  factory :config_version do
    project
    version_id { "v#{SecureRandom.hex(8)}" }
    change_type { "create" }
    change_summary { "Initial configuration" }
    changed_by_sub { "user-sub-#{SecureRandom.hex(4)}" }
    snapshot { {} }

    trait :create do
      change_type { "create" }
    end

    trait :update do
      change_type { "update" }
      change_summary { "Configuration updated" }
    end

    trait :rollback do
      change_type { "rollback" }
      change_summary { "Rolled back to previous version" }
    end
  end
end
