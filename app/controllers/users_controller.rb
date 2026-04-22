class UsersController < ApplicationController
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
end
