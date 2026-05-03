require "rails_helper"

RSpec.describe ProjectApiKey, type: :model do
  subject { build(:project_api_key) }

  describe "validations" do
    it { is_expected.to belong_to(:project) }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:token_digest) }
    it { is_expected.to validate_presence_of(:token_prefix) }
    it { is_expected.to validate_uniqueness_of(:token_digest) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:project_id) }
  end

  describe ".digest_token" do
    it "returns a SHA256 digest without storing the plaintext token" do
      token = "pak-test-token"

      expect(described_class.digest_token(token)).to eq(Digest::SHA256.hexdigest(token))
    end
  end

  describe ".active" do
    it "returns keys that have not been revoked" do
      active_key = create(:project_api_key)
      create(:project_api_key, :revoked, project: active_key.project)

      expect(described_class.active).to contain_exactly(active_key)
    end
  end

  describe "#revoked?" do
    it "returns true when revoked_at is present" do
      expect(build(:project_api_key, :revoked)).to be_revoked
    end
  end
end
