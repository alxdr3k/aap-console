class SessionsController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :create, :destroy, :failure ]

  def create
    auth = request.env["omniauth.auth"]
    raw_info = auth.extra.raw_info
    realm_roles = raw_info.dig("realm_access", "roles") || []

    session[:user_sub] = auth.uid
    session[:realm_roles] = realm_roles

    update_joined_at(auth.uid)

    redirect_to organizations_path
  end

  def destroy
    reset_session
    redirect_to root_path, allow_other_host: false
  end

  def failure
    redirect_to root_path, alert: "Authentication failed: #{params[:message]}"
  end

  private

  def update_joined_at(user_sub)
    OrgMembership.where(user_sub: user_sub, joined_at: nil).update_all(joined_at: Time.current)
  end
end
