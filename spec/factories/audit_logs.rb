FactoryBot.define do
  factory :audit_log do
    organization
    project
    user_sub { "user-sub-#{SecureRandom.hex(4)}" }
    action { "project.create" }
    resource_type { "Project" }
    resource_id { SecureRandom.uuid }
    details { {} }
  end
end
