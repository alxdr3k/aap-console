require "rails_helper"

RSpec.describe Organizations::UpdateService do
  include LangfuseMock

  let(:user_sub) { "user-sub-admin" }
  let(:organization) { create(:organization, name: "Acme Corp", langfuse_org_id: "lf-org-1") }

  before do
    stub_langfuse_login
  end

  describe "#call" do
    it "updates local organization metadata" do
      stub_langfuse_update_org(org_id: "lf-org-1", name: "New Name")

      result = described_class.new(
        organization: organization,
        params: { name: "New Name", description: "Updated" },
        current_user_sub: user_sub
      ).call

      expect(result).to be_success
      expect(organization.reload.name).to eq("New Name")
      expect(organization.description).to eq("Updated")
    end

    it "syncs name changes to Langfuse" do
      stub_langfuse_update_org(org_id: "lf-org-1", name: "New Name")

      described_class.new(
        organization: organization,
        params: { name: "New Name" },
        current_user_sub: user_sub
      ).call

      expect(WebMock).to have_requested(:post, %r{/api/trpc/organizations\.update})
    end

    it "does not call Langfuse when only description changes" do
      result = described_class.new(
        organization: organization,
        params: { description: "Updated" },
        current_user_sub: user_sub
      ).call

      expect(result).to be_success
      expect(WebMock).not_to have_requested(:post, %r{/api/trpc/organizations\.update})
    end

    it "writes an audit log with changed fields" do
      stub_langfuse_update_org(org_id: "lf-org-1", name: "New Name")

      expect {
        described_class.new(
          organization: organization,
          params: { name: "New Name" },
          current_user_sub: user_sub
        ).call
      }.to change(AuditLog, :count).by(1)

      expect(AuditLog.last.details["changed_fields"]).to include("name")
    end

    it "returns failure and keeps local state when Langfuse update fails" do
      stub_langfuse_update_org(org_id: "lf-org-1", name: "New Name", status: 500)

      result = described_class.new(
        organization: organization,
        params: { name: "New Name" },
        current_user_sub: user_sub
      ).call

      expect(result).to be_failure
      expect(organization.reload.name).to eq("Acme Corp")
    end
  end
end
