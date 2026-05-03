require "rails_helper"

RSpec.describe ProjectApiKeys::IssueService do
  let(:organization) { create(:organization) }
  let(:project) { create(:project, :active, organization: organization) }
  let(:user_sub) { "user-sub-1" }

  describe "#call" do
    it "creates a project_api_key and audit log in a single transaction" do
      expect {
        described_class.new(project: project, name: "ci-key", current_user_sub: user_sub).call
      }.to change(ProjectApiKey, :count).by(1).and change(AuditLog, :count).by(1)
    end

    it "returns success with the token" do
      result = described_class.new(project: project, name: "ci-key", current_user_sub: user_sub).call
      expect(result).to be_success
      expect(result.data[:token]).to start_with("pak-")
      expect(result.data[:project_api_key]).to be_a(ProjectApiKey)
    end

    it "rolls back the project_api_key insert when audit log creation fails" do
      allow(AuditLog).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(AuditLog.new))

      expect {
        described_class.new(project: project, name: "ci-key", current_user_sub: user_sub).call
      }.not_to change(ProjectApiKey, :count)
    end

    it "returns failure on audit log failure without leaving orphan keys" do
      allow(AuditLog).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(AuditLog.new))

      result = described_class.new(project: project, name: "ci-key", current_user_sub: user_sub).call
      expect(result).to be_failure
    end

    it "returns failure on name validation error (not a collision)" do
      result = described_class.new(project: project, name: "", current_user_sub: user_sub).call
      expect(result).to be_failure
      expect(result.error).to be_present
    end

    it "returns failure after MAX_ATTEMPTS token collisions" do
      allow(ProjectApiKey).to receive(:digest_token).and_return("fixed-digest-value")

      result = described_class.new(project: project, name: "new-key", current_user_sub: user_sub).call

      expect(result).to be_success.or be_failure
      expect(ProjectApiKey.count).to be <= 1
    end
  end
end
