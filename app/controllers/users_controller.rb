class UsersController < ApplicationController
  before_action :authorize_user_search!

  def search
    query = params[:q]

    if query.blank?
      return render json: { error: "Query parameter q is required" }, status: :bad_request
    end

    keycloak_client = KeycloakClient.new
    users = keycloak_client.search_users(query: query)

    render json: { users: users }
  rescue BaseClient::ApiError => e
    render json: { error: "Keycloak search failed: #{e.message}" }, status: :service_unavailable
  end

  private

  def authorize_user_search!
    return if current_authorization.super_admin?
    return if OrgMembership.exists?(user_sub: Current.user_sub, role: "admin")

    render_forbidden
  end
end
