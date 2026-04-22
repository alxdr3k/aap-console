require "rails_helper"

RSpec.describe Project, type: :model do
  subject { build(:project) }

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:app_id) }
    it { is_expected.to validate_length_of(:name).is_at_least(2).is_at_most(100) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:organization) }
    it { is_expected.to have_one(:project_auth_config).dependent(:destroy) }
    it { is_expected.to have_many(:project_api_keys).dependent(:destroy) }
    it { is_expected.to have_many(:project_permissions).dependent(:destroy) }
    it { is_expected.to have_many(:provisioning_jobs).dependent(:destroy) }
    it { is_expected.to have_many(:config_versions).dependent(:destroy) }
    it { is_expected.to have_many(:audit_logs) }
  end

  describe "status enum" do
    it { is_expected.to define_enum_for(:status).with_values(
      provisioning: 0, active: 1, update_pending: 2,
      deleting: 3, deleted: 4, provision_failed: 5
    ) }
  end

  describe "app_id generation" do
    it "auto-generates app_id before validation" do
      project = build(:project, app_id: nil)
      project.valid?
      expect(project.app_id).to match(/\Aapp-[a-zA-Z0-9]{12}\z/)
    end

    it "does not regenerate app_id if already set" do
      project = build(:project, app_id: "app-existingidXX")
      project.valid?
      expect(project.app_id).to eq("app-existingidXX")
    end
  end

  describe "slug generation" do
    it "auto-generates slug from name if not provided" do
      org = create(:organization)
      project = Project.new(name: "My Chatbot", organization: org)
      project.valid?
      expect(project.slug).to eq("my-chatbot")
    end
  end

  describe "scopes" do
    it ".active returns only active projects" do
      active = create(:project, :active)
      create(:project, :provisioning)
      expect(Project.active).to contain_exactly(active)
    end
  end
end
