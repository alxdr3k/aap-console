require "rails_helper"

RSpec.describe ProvisioningJobsCleanupJob, type: :job do
  let(:project) { create(:project) }

  describe "#perform" do
    it "deletes successful terminal jobs older than the retention window with their steps" do
      old_completed = create_old_job(:completed)
      old_completed_with_warnings = create_old_job(:completed_with_warnings)
      old_rolled_back = create_old_job(:rolled_back)
      old_step = create(:provisioning_step, :completed, provisioning_job: old_completed)

      recent_completed = create_recent_job(:completed)
      failed = create_old_job(:failed)
      rollback_failed = create_old_job(:rollback_failed)
      active = create_old_job(:in_progress)

      result = described_class.perform_now

      expect(result).to include(
        deleted: 3,
        retention_days: described_class::RETENTION_DAYS,
        cleanup_statuses: described_class::CLEANUP_STATUSES,
        preserved_statuses: described_class::PRESERVED_STATUSES
      )
      expect(ProvisioningJob.where(id: [
        old_completed.id,
        old_completed_with_warnings.id,
        old_rolled_back.id
      ])).to be_empty
      expect(ProvisioningStep.where(id: old_step.id)).to be_empty
      expect(ProvisioningJob.where(id: [
        recent_completed.id,
        failed.id,
        rollback_failed.id,
        active.id
      ])).to contain_exactly(recent_completed, failed, rollback_failed, active)
    end

    it "keeps config versions by nullifying the provisioning job reference" do
      old_job = create_old_job(:completed)
      config_version = create(:config_version, project: project, provisioning_job: old_job)
      rollback_version = create(:config_version, :rollback, project: project, provisioning_job: old_job)

      expect { described_class.perform_now }
        .to change { config_version.reload.provisioning_job_id }
        .from(old_job.id)
        .to(nil)
        .and change { rollback_version.reload.provisioning_job_id }
        .from(old_job.id)
        .to(nil)
      expect(ProvisioningJob.exists?(old_job.id)).to be(false)
    end

    it "uses updated_at as the cutoff fallback when completed_at is missing" do
      old_job = create_old_job(:completed)
      old_job.update_columns(completed_at: nil, updated_at: 181.days.ago)

      expect { described_class.perform_now }
        .to change { ProvisioningJob.exists?(old_job.id) }
        .from(true)
        .to(false)
    end

    it "honors a custom retention window" do
      job = create_recent_job(:completed, age: 45.days)

      expect { described_class.perform_now(retention_days: 30) }
        .to change { ProvisioningJob.exists?(job.id) }
        .from(true)
        .to(false)
    end
  end

  def create_old_job(status)
    create_job(status, age: 181.days)
  end

  def create_recent_job(status, age: 30.days)
    create_job(status, age: age)
  end

  def create_job(status, age:)
    timestamp = age.ago

    create(
      :provisioning_job,
      status,
      project: project,
      started_at: timestamp - 1.minute,
      completed_at: terminal_status?(status) ? timestamp : nil,
      created_at: timestamp - 2.minutes,
      updated_at: timestamp
    )
  end

  def terminal_status?(status)
    ProvisioningJob::TERMINAL_STATUSES.include?(status.to_s)
  end
end
