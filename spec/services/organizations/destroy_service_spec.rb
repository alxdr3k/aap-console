require "rails_helper"

RSpec.describe Organizations::DestroyService do
  let(:organization) { create(:organization, langfuse_org_id: "langfuse-org-123") }
  let(:user_sub) { "user-sub-123" }

  describe "#call" do
    context "with no projects" do
      before do
        stub_langfuse_delete_org(org_id: organization.langfuse_org_id)
      end

      it "deletes the organization from DB" do
        expect {
          described_class.new(organization: organization, current_user_sub: user_sub).call
        }.to change(Organization, :count).by(-1)
      end

      it "deletes the Langfuse org" do
        described_class.new(organization: organization, current_user_sub: user_sub).call
        expect(WebMock).to have_requested(:post, %r{organizations\.delete})
      end

      it "writes an audit log" do
        expect {
          described_class.new(organization: organization, current_user_sub: user_sub).call
        }.to change(AuditLog, :count).by(1)

        log = AuditLog.last
        expect(log.action).to eq("org.destroy")
        expect(log.user_sub).to eq(user_sub)
      end

      it "returns success" do
        result = described_class.new(organization: organization, current_user_sub: user_sub).call
        expect(result).to be_success
      end
    end

    context "with active projects" do
      let!(:project) { create(:project, :active, organization: organization) }

      before do
        stub_langfuse_delete_org(org_id: organization.langfuse_org_id)
      end

      it "initiates project deletion first" do
        described_class.new(organization: organization, current_user_sub: user_sub).call
        expect(project.reload.status).to eq("deleting")
      end
    end

    context "without a Langfuse org ID" do
      let(:organization) { create(:organization, langfuse_org_id: nil) }

      it "skips Langfuse deletion and still succeeds" do
        result = described_class.new(organization: organization, current_user_sub: user_sub).call
        expect(result).to be_success
        expect(WebMock).not_to have_requested(:post, %r{organizations\.delete})
      end
    end
  end
end
