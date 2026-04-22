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
    if @membership.update(role: params.require(:member).permit(:role)[:role])
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
end
