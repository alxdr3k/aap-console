class AddInputSnapshotToProvisioningJobs < ActiveRecord::Migration[8.1]
  def change
    # JSON snapshot of the externally-relevant input params (e.g.
    # redirect_uris, models, s3_retention_days). Manual retry replays the
    # provisioning from this column instead of trusting ActiveJob args,
    # which can be lost across worker crashes or operator-initiated retries.
    add_column :provisioning_jobs, :input_snapshot, :json
  end
end
