require "rails_helper"

RSpec.describe Organizations::CreateService do
  include LangfuseMock
  include KeycloakMock

  let(:user_sub) { "user-sub-admin" }
  let(:params) { { name: "Acme Corp", description: "Test org" } }

  before do
    stub_langfuse_login
    stub_langfuse_create_org(name: "Acme Corp", org_id: "langfuse-org-1")
  end

  describe "#call" do
    it "creates the organization in the DB" do
      result = described_class.new(params: params, current_user_sub: user_sub).call
      expect(result).to be_success
      expect(result.data).to be_a(Organization)
      expect(result.data.name).to eq("Acme Corp")
      expect(result.data).to be_persisted
    end

    it "creates an admin membership for the creator" do
      result = described_class.new(params: params, current_user_sub: user_sub).call
      org = result.data
      membership = org.org_memberships.find_by(user_sub: user_sub)
      expect(membership).to be_present
      expect(membership.role).to eq("admin")
      expect(membership.joined_at).to be_present
    end

    it "creates a pending admin membership for a designated initial admin who is not the creator" do
      stub_keycloak_get_user(user_sub: "selected-admin-sub")

      result = described_class.new(
        params: params.merge(initial_admin_user_sub: "selected-admin-sub"),
        current_user_sub: user_sub
      ).call
      org = result.data
      membership = org.org_memberships.find_by(user_sub: "selected-admin-sub")

      expect(membership.role).to eq("admin")
      expect(membership.joined_at).to be_nil
      expect(org.org_memberships.find_by(user_sub: user_sub)).to be_nil
    end

    it "returns failure when initial_admin_user_sub does not exist in Keycloak" do
      stub_keycloak_get_user(user_sub: "nonexistent-sub", status: 404)

      result = described_class.new(
        params: params.merge(initial_admin_user_sub: "nonexistent-sub"),
        current_user_sub: user_sub
      ).call

      expect(result).to be_failure
      expect(result.error).to include("not found")
      expect(Organization.count).to eq(0)
    end

    it "stores the langfuse_org_id" do
      result = described_class.new(params: params, current_user_sub: user_sub).call
      expect(result.data.langfuse_org_id).to eq("langfuse-org-1")
    end

    it "writes an audit log" do
      expect {
        described_class.new(params: params, current_user_sub: user_sub).call
      }.to change(AuditLog, :count).by(1)
    end

    it "returns failure when name is blank" do
      result = described_class.new(params: { name: "" }, current_user_sub: user_sub).call
      expect(result).to be_failure
    end

    it "returns failure when Langfuse API fails" do
      stub_langfuse_login
      stub_langfuse_create_org(name: "Acme Corp", org_id: nil, status: 500)
      result = described_class.new(params: params, current_user_sub: user_sub).call
      expect(result).to be_failure
      expect(Organization.count).to eq(0)
    end

    it "compensates the Langfuse org if the DB transaction raises" do
      stub_langfuse_delete_org(org_id: "langfuse-org-1")

      # Force the DB transaction to fail after the Langfuse call.
      allow(AuditLog).to receive(:create!)
        .and_raise(ActiveRecord::RecordInvalid.new(AuditLog.new))

      result = described_class.new(params: params, current_user_sub: user_sub).call

      expect(result).to be_failure
      expect(Organization.count).to eq(0)
      expect(WebMock).to have_requested(:post, %r{/api/trpc/organizations\.delete}).at_least_once
    end
  end
end
