class MembersController < ApplicationController
  before_action :set_organization
  before_action -> { authorize_org!(@organization) }, only: [ :index ]
  before_action -> { authorize_org!(@organization, minimum_role: :admin) }, only: [ :create, :update, :destroy ]
  before_action :set_membership, only: [ :update, :destroy ]

  def index
    memberships = @organization.org_memberships.order(:created_at)
    render json: memberships
  end

  def create
    user_sub = params.dig(:member, :user_sub).to_s.strip
    role = params.dig(:member, :role)

    if user_sub.blank?
      return render json: { errors: [ "user_sub can't be blank" ] }, status: :unprocessable_entity
    end

    membership = @organization.org_memberships.build(
      user_sub: user_sub,
      role: role,
      invited_at: Time.current
    )

    if membership.save
      AuditLog.create!(
        organization: @organization,
        user_sub: Current.user_sub,
        action: "member.add",
        resource_type: "OrgMembership",
        resource_id: membership.id.to_s,
        details: { added_user_sub: user_sub, role: role }
      )
      render json: membership, status: :created
    else
      render json: { errors: membership.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    new_role = params.require(:member).permit(:role)[:role]

    if demoting_last_admin?(@membership, new_role)
      return render json: { error: "Cannot demote the last admin of this organization" },
                    status: :unprocessable_entity
    end

    if @membership.update(role: new_role)
      AuditLog.create!(
        organization: @organization,
        user_sub: Current.user_sub,
        action: "member.update",
        resource_type: "OrgMembership",
        resource_id: @membership.id.to_s,
        details: { user_sub: @membership.user_sub, role: @membership.role }
      )
      render json: @membership
    else
      render json: { errors: @membership.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    if removing_last_admin?(@membership)
      return render json: { error: "Cannot remove the last admin of this organization" },
                    status: :unprocessable_entity
    end

    @membership.destroy!
    AuditLog.create!(
      organization: @organization,
      user_sub: Current.user_sub,
      action: "member.remove",
      resource_type: "OrgMembership",
      resource_id: @membership.id.to_s,
      details: { removed_user_sub: @membership.user_sub }
    )
    render json: { message: "Member removed" }
  end

  private

  def set_organization
    @organization = Organization.find_by!(slug: params[:organization_slug])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Not found" }, status: :not_found
  end

  def set_membership
    @membership = @organization.org_memberships.find_by!(user_sub: params[:user_sub])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Not found" }, status: :not_found
  end

  # An admin being downgraded to a non-admin role counts as demotion.
  # If they are the only admin in the org, block it — the org would be
  # left without a manager.
  def demoting_last_admin?(membership, new_role)
    return false unless membership.role == "admin"
    return false if new_role.to_s == "admin"
    last_admin?(membership)
  end

  def removing_last_admin?(membership)
    return false unless membership.role == "admin"
    last_admin?(membership)
  end

  def last_admin?(membership)
    @organization.org_memberships.where(role: "admin").where.not(id: membership.id).none?
  end
end
