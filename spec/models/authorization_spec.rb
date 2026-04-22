require "rails_helper"

RSpec.describe Authorization do
  let(:organization) { create(:organization) }
  let(:project) { create(:project, :active, organization: organization) }

  describe "#super_admin?" do
    it "returns true when realm_roles contains super_admin" do
      auth = described_class.new(user_sub: "u1", realm_roles: ["super_admin"])
      expect(auth.super_admin?).to be true
    end

    it "returns false when realm_roles does not contain super_admin" do
      auth = described_class.new(user_sub: "u1", realm_roles: ["user"])
      expect(auth.super_admin?).to be false
    end
  end

  describe "#org_membership" do
    it "returns the membership for the given org" do
      membership = create(:org_membership, organization: organization, user_sub: "u1", role: "write")
      auth = described_class.new(user_sub: "u1", realm_roles: [])
      expect(auth.org_membership(organization)).to eq(membership)
    end

    it "returns nil when no membership exists" do
      auth = described_class.new(user_sub: "unknown", realm_roles: [])
      expect(auth.org_membership(organization)).to be_nil
    end
  end

  describe "#project_role" do
    context "when user is super_admin" do
      it "returns :admin" do
        auth = described_class.new(user_sub: "u1", realm_roles: ["super_admin"])
        expect(auth.project_role(project)).to eq(:admin)
      end
    end

    context "when user is org admin" do
      it "returns :admin" do
        create(:org_membership, organization: organization, user_sub: "u1", role: "admin")
        auth = described_class.new(user_sub: "u1", realm_roles: [])
        expect(auth.project_role(project)).to eq(:admin)
      end
    end

    context "when user has explicit project permission" do
      it "returns the permission role as symbol" do
        membership = create(:org_membership, organization: organization, user_sub: "u1", role: "read")
        create(:project_permission, org_membership: membership, project: project, role: "write")
        auth = described_class.new(user_sub: "u1", realm_roles: [])
        expect(auth.project_role(project)).to eq(:write)
      end
    end

    context "when user has no access" do
      it "returns nil" do
        auth = described_class.new(user_sub: "u1", realm_roles: [])
        expect(auth.project_role(project)).to be_nil
      end
    end
  end

  describe "#accessible_projects" do
    let!(:project2) { create(:project, :active, organization: organization) }

    context "when user is org admin" do
      it "returns all projects in the org" do
        create(:org_membership, organization: organization, user_sub: "u1", role: "admin")
        auth = described_class.new(user_sub: "u1", realm_roles: [])
        expect(auth.accessible_projects(organization)).to match_array([project, project2])
      end
    end

    context "when user has explicit project permissions" do
      it "returns only permitted projects" do
        membership = create(:org_membership, organization: organization, user_sub: "u1", role: "read")
        create(:project_permission, org_membership: membership, project: project, role: "read")
        auth = described_class.new(user_sub: "u1", realm_roles: [])
        expect(auth.accessible_projects(organization)).to contain_exactly(project)
      end
    end
  end

  describe "#organizations" do
    it "returns organizations the user is a member of" do
      other_org = create(:organization)
      create(:org_membership, organization: organization, user_sub: "u1")
      create(:org_membership, organization: other_org, user_sub: "u2")
      auth = described_class.new(user_sub: "u1", realm_roles: [])
      expect(auth.organizations).to contain_exactly(organization)
    end
  end
end
