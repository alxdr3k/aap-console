require "rails_helper"

RSpec.describe ProvisioningJob, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:operation) }
    it { is_expected.to validate_inclusion_of(:operation).in_array(%w[create update delete]) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:project) }
    it { is_expected.to have_many(:provisioning_steps).dependent(:destroy) }
    it { is_expected.to have_one(:config_version) }
  end

  describe "status enum" do
    it { is_expected.to define_enum_for(:status).with_values(
      pending: 0, in_progress: 1, completed: 2,
      completed_with_warnings: 3, failed: 4, retrying: 5,
      rolling_back: 6, rolled_back: 7, rollback_failed: 8
    ) }
  end

  describe "#active?" do
    it "returns true for pending, in_progress, retrying, rolling_back" do
      %w[pending in_progress retrying rolling_back].each do |status|
        job = build(:provisioning_job, status: status)
        expect(job.active?).to be(true), "expected #{status} to be active"
      end
    end

    it "returns false for terminal states" do
      %w[completed completed_with_warnings failed rolled_back rollback_failed].each do |status|
        job = build(:provisioning_job, status: status)
        expect(job.active?).to be(false), "expected #{status} to not be active"
      end
    end
  end

  describe "concurrent job constraint" do
    it "prevents creating a second active job for the same project" do
      project = create(:project)
      create(:provisioning_job, project: project, status: :in_progress)
      duplicate = build(:provisioning_job, project: project, status: :pending)
      expect { duplicate.save! }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows a new job after the previous one completes" do
      project = create(:project)
      create(:provisioning_job, project: project, status: :completed)
      new_job = build(:provisioning_job, project: project, status: :pending)
      expect(new_job).to be_valid
    end
  end
end
