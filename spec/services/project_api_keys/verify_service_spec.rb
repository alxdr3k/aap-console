require "rails_helper"

RSpec.describe ProjectApiKeys::VerifyService do
  let(:organization) { create(:organization) }
  let(:project) { create(:project, :active, organization: organization) }
  let(:token) { "pak-#{SecureRandom.alphanumeric(40)}" }
  let!(:project_api_key) do
    create(:project_api_key,
      project: project,
      token_digest: ProjectApiKey.digest_token(token),
      token_prefix: token.first(ProjectApiKey::TOKEN_PREFIX_LENGTH))
  end

  describe "#call" do
    it "returns success and updates last_used_at for a valid active token" do
      result = described_class.new(token: token).call
      expect(result).to be_success
      expect(result.data.last_used_at).to be_present
    end

    it "returns failure for an empty token" do
      expect(described_class.new(token: "").call).to be_failure
    end

    it "returns failure for an unknown token" do
      result = described_class.new(token: "pak-unknowntoken").call
      expect(result).to be_failure
      expect(result.error).to eq("Invalid token")
    end

    it "returns failure when token is revoked" do
      project_api_key.update!(revoked_at: Time.current)
      result = described_class.new(token: token).call
      expect(result).to be_failure
    end

    it "returns failure when project is not in a verifiable status" do
      project.update!(status: :provisioning)
      result = described_class.new(token: token).call
      expect(result).to be_failure
      expect(result.error).to eq("Invalid token")
    end

    it "returns failure when update_all matches 0 rows (race window)" do
      allow(ProjectApiKey).to receive_message_chain(:active, :joins, :where, :where, :update_all).and_return(0)
      result = described_class.new(token: token).call
      expect(result).to be_failure
      expect(result.error).to eq("Invalid token")
    end

    it "returns failure gracefully when find_by returns nil after update_all succeeds (TOCTOU)" do
      allow(ProjectApiKey).to receive(:includes).and_return(
        double(find_by: nil)
      )
      allow_any_instance_of(ActiveRecord::Relation).to receive(:update_all).and_return(1)

      result = described_class.new(token: token).call
      expect(result).to be_failure
      expect(result.error).to eq("Invalid token")
    end
  end
end
