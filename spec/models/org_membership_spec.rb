require "rails_helper"

RSpec.describe OrgMembership, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:user_sub) }
    it { is_expected.to validate_presence_of(:role) }
    it { is_expected.to validate_inclusion_of(:role).in_array(%w[admin write read]) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:organization) }
    it { is_expected.to have_many(:project_permissions).dependent(:destroy) }
  end

  describe "uniqueness" do
    it "prevents duplicate membership for same user in same org" do
      org = create(:organization)
      create(:org_membership, organization: org, user_sub: "user-123")
      duplicate = build(:org_membership, organization: org, user_sub: "user-123")
      expect(duplicate).not_to be_valid
    end
  end

  describe "#admin?" do
    it "returns true for admin role" do
      membership = build(:org_membership, role: "admin")
      expect(membership.admin?).to be true
    end

    it "returns false for non-admin roles" do
      expect(build(:org_membership, role: "write").admin?).to be false
      expect(build(:org_membership, role: "read").admin?).to be false
    end
  end
end
