require "rails_helper"

RSpec.describe Organization, type: :model do
  subject { build(:organization) }

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:slug) }
    it { is_expected.to validate_length_of(:name).is_at_least(2).is_at_most(100) }
  end

  describe "associations" do
    it { is_expected.to have_many(:projects).dependent(:destroy) }
    it { is_expected.to have_many(:org_memberships).dependent(:destroy) }
    it { is_expected.to have_many(:audit_logs) }
  end

  describe "slug generation" do
    it "auto-generates slug from name if not provided" do
      org = Organization.new(name: "Acme Corp")
      org.valid?
      expect(org.slug).to eq("acme-corp")
    end

    it "does not overwrite an explicitly set slug" do
      org = Organization.new(name: "Acme Corp", slug: "my-custom-slug")
      org.valid?
      expect(org.slug).to eq("my-custom-slug")
    end
  end
end
