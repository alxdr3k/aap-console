require "rails_helper"

RSpec.describe OrganizationDestroyFinalizeJob, type: :job do
  let(:organization) { create(:organization, langfuse_org_id: "langfuse-org-123") }
  let(:user_sub) { "user-sub-123" }

  describe "#perform" do
    it "reschedules itself while projects are still deleting" do
      project = create(:project, :deleting, organization: organization)
      create(:provisioning_job, :in_progress, project: project, operation: "delete")

      expect {
        described_class.perform_now(organization.id, current_user_sub: user_sub)
      }.to have_enqueued_job(described_class)

      expect(organization.reload).to be_present
      expect(organization.destroy_finalizer_reserved_until).to be_future
    end

    it "finalizes organization deletion after all projects are deleted" do
      create(:project, :deleted, organization: organization)
      stub_langfuse_delete_org(org_id: organization.langfuse_org_id)

      expect {
        described_class.perform_now(organization.id, current_user_sub: user_sub)
      }.to change(Organization, :count).by(-1)

      expect(WebMock).to have_requested(:post, %r{organizations\.delete})
    end

    it "re-enqueues itself when final organization deletion fails" do
      create(:project, :deleted, organization: organization)
      stub_langfuse_delete_org(org_id: organization.langfuse_org_id, status: 500)
      allow(Rails.logger).to receive(:error)

      expect {
        described_class.perform_now(organization.id, current_user_sub: user_sub)
      }.to have_enqueued_job(described_class)

      expect(organization.reload).to be_present
      expect(Rails.logger).to have_received(:error).with(/Failed to finalize organization/)
    end

    it "re-enqueues itself when final organization deletion is deferred" do
      create(:project, :deleted, organization: organization)
      service = instance_double(Organizations::DestroyService, call: Result.success(deferred: true))
      allow(Organizations::DestroyService).to receive(:new)
        .with(organization: organization, current_user_sub: user_sub)
        .and_return(service)

      expect {
        described_class.perform_now(organization.id, current_user_sub: user_sub)
      }.to have_enqueued_job(described_class)
    end

    it "no-ops when the organization is already gone" do
      expect {
        described_class.perform_now(-1, current_user_sub: user_sub)
      }.not_to have_enqueued_job(described_class)
    end

    it "reschedules with a backoff and releases the reservation when a remaining project has no active delete job" do
      create(:project, :provision_failed, organization: organization, slug: "blocked-project")
      organization.update!(destroy_finalizer_reserved_until: 5.minutes.from_now)
      allow(Rails.logger).to receive(:warn)

      expect {
        described_class.perform_now(organization.id, current_user_sub: user_sub)
      }.to have_enqueued_job(described_class)
        .and change { AuditLog.where(action: "organization.destroy.blocked").count }.by(1)

      # Releasing the reservation allows operator-driven recovery paths to
      # call enqueue_once immediately rather than waiting for the lease.
      expect(organization.reload.destroy_finalizer_reserved_until).to be_nil
      expect(Rails.logger).to have_received(:warn).with(/blocked-project:provision_failed/)
      audit = AuditLog.where(action: "organization.destroy.blocked").last
      expect(audit.organization).to eq(organization)
      expect(audit.details["remaining_projects"]).to include("blocked-project:provision_failed")
    end

    it "reschedules with a backoff and releases the reservation when a deleting project has no active delete job" do
      create(:project, :deleting, organization: organization, slug: "stalled-project")
      organization.update!(destroy_finalizer_reserved_until: 5.minutes.from_now)
      allow(Rails.logger).to receive(:warn)

      expect {
        described_class.perform_now(organization.id, current_user_sub: user_sub)
      }.to have_enqueued_job(described_class)

      expect(organization.reload.destroy_finalizer_reserved_until).to be_nil
      expect(Rails.logger).to have_received(:warn).with(/stalled-project:deleting/)
    end
  end
end
