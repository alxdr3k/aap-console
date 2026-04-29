require "rails_helper"

RSpec.describe OrganizationDestroyFinalizeJob, type: :job do
  let(:organization) { create(:organization, langfuse_org_id: "langfuse-org-123") }
  let(:user_sub) { "user-sub-123" }

  describe "#perform" do
    it "reschedules itself while projects are still deleting" do
      create(:project, :deleting, organization: organization)

      expect {
        described_class.perform_now(organization.id, current_user_sub: user_sub)
      }.to have_enqueued_job(described_class)

      expect(organization.reload).to be_present
    end

    it "finalizes organization deletion after all projects are deleted" do
      create(:project, :deleted, organization: organization)
      stub_langfuse_delete_org(org_id: organization.langfuse_org_id)

      expect {
        described_class.perform_now(organization.id, current_user_sub: user_sub)
      }.to change(Organization, :count).by(-1)

      expect(WebMock).to have_requested(:post, %r{organizations\.delete})
    end

    it "no-ops when the organization is already gone" do
      expect {
        described_class.perform_now(-1, current_user_sub: user_sub)
      }.not_to have_enqueued_job(described_class)
    end

    it "stops rescheduling when remaining projects are not in a delete flow" do
      create(:project, :provision_failed, organization: organization, slug: "blocked-project")
      allow(Rails.logger).to receive(:error)

      expect {
        described_class.perform_now(organization.id, current_user_sub: user_sub)
      }.not_to have_enqueued_job(described_class)

      expect(Rails.logger).to have_received(:error).with(/blocked-project:provision_failed/)
    end
  end
end
