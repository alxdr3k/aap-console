require "rails_helper"

RSpec.describe ProvisioningChannel, type: :channel do
  let(:organization) { create(:organization) }
  let(:project) { create(:project, :active, organization: organization) }
  let(:provisioning_job) { create(:provisioning_job, project: project) }

  describe "#subscribed" do
    context "when job exists and user has access" do
      before do
        stub_connection(current_user_sub: "user-123")
        create(:org_membership, organization: organization, user_sub: "user-123", role: "admin")
      end

      it "subscribes to the job stream" do
        subscribe(job_id: provisioning_job.id)
        expect(subscription).to be_confirmed
        expect(subscription).to have_stream_for(provisioning_job)
      end
    end

    context "when job does not exist" do
      before { stub_connection(current_user_sub: "user-123") }

      it "rejects the subscription" do
        subscribe(job_id: 99999)
        expect(subscription).to be_rejected
      end
    end

    context "when user has no access to the project" do
      before do
        stub_connection(current_user_sub: "other-user")
      end

      it "rejects the subscription" do
        subscribe(job_id: provisioning_job.id)
        expect(subscription).to be_rejected
      end
    end
  end
end
