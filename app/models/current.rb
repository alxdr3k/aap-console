class Current < ActiveSupport::CurrentAttributes
  attribute :user_sub, :realm_roles, :request_id

  def super_admin?
    Array(realm_roles).include?("super_admin")
  end
end
