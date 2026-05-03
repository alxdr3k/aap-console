class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  before_action :authenticate_user!
  before_action :set_current_user

  helper_method :current_authorization

  protected

  def authenticate_user!
    return if session[:user_sub].present?

    # OmniAuth (with omniauth-rails_csrf_protection) only accepts POST on
    # /auth/:provider — a GET redirect would be rejected as CSRF. Render a
    # tiny page that auto-submits a CSRF-tokenized POST. See
    # config/initializers/omniauth.rb for the rationale.
    respond_to do |format|
      format.html { render "sessions/login", status: :unauthorized, layout: false }
      format.json { render json: { error: "Authentication required" }, status: :unauthorized }
    end
  end

  def set_current_user
    Current.user_sub = session[:user_sub]
    Current.realm_roles = session[:realm_roles] || []
    Current.request_id = request.uuid
  end

  def current_authorization
    @current_authorization ||= Authorization.new(
      user_sub: Current.user_sub,
      realm_roles: Current.realm_roles
    )
  end

  def require_super_admin!
    return if current_authorization.super_admin?

    render_forbidden
  end

  def authorize_org!(organization, minimum_role: :read)
    return if current_authorization.super_admin?

    membership = current_authorization.org_membership(organization)
    unless membership && role_sufficient?(membership.role.to_sym, minimum_role)
      render_forbidden
    end
  end

  def authorize_project!(project, minimum_role: :read)
    return if current_authorization.super_admin?

    role = current_authorization.project_role(project)
    unless role && role_sufficient?(role, minimum_role)
      render_forbidden
    end
  end

  def render_forbidden
    respond_to do |format|
      format.html { render plain: "Forbidden", status: :forbidden }
      format.json { render json: { error: "Forbidden" }, status: :forbidden }
    end
  end

  def default_json_request?
    return false if params[:format].present?

    accept_header = request.get_header("HTTP_ACCEPT").to_s.strip
    accept_header.blank? || accept_header == "*/*" || request.accepts == [ Mime::ALL ]
  end

  def json_request?
    request.format.json? || default_json_request?
  end

  def prefer_json_for_default_requests
    request.format = :json if default_json_request?
  end

  protected

  ROLE_HIERARCHY = { read: 1, write: 2, admin: 3 }.freeze

  def role_sufficient?(actual_role, required_role)
    ROLE_HIERARCHY.fetch(actual_role, 0) >= ROLE_HIERARCHY.fetch(required_role, 0)
  end
end
