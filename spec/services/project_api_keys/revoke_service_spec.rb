require "rails_helper"

RSpec.describe ProjectApiKeys::RevokeService do
  describe "#call" do
    it "returns reloaded state when another request already revoked the key" do
      project_api_key = create(:project_api_key)
      stale_project_api_key = ProjectApiKey.find(project_api_key.id)
      revoked_at = Time.current
      ProjectApiKey.where(id: project_api_key.id).update_all(revoked_at: revoked_at, updated_at: revoked_at)

      expect {
        result = described_class.new(
          project_api_key: stale_project_api_key,
          current_user_sub: "user-1"
        ).call

        expect(result).to be_success
        expect(result.data.revoked_at).to be_present
      }.not_to change { AuditLog.where(action: "project_api_key.revoke").count }
    end
  end
end
