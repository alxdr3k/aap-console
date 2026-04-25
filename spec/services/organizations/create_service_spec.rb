require "rails_helper"

RSpec.describe Organizations::CreateService do
  include LangfuseMock

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
