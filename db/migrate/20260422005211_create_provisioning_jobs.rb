class CreateProvisioningJobs < ActiveRecord::Migration[8.1]
  def change
    create_table :provisioning_jobs do |t|
      t.references :project, null: false, foreign_key: true
      t.string :operation, null: false
      t.integer :status, null: false, default: 0
      t.datetime :started_at
      t.datetime :completed_at
      t.text :error_message
      t.json :warnings

      t.timestamps
    end

    add_index :provisioning_jobs, [ :project_id, :status ]
    add_index :provisioning_jobs, :status
    # Enforce at most one active job per project (pending/in_progress/retrying/rolling_back)
    add_index :provisioning_jobs, :project_id,
              unique: true,
              where: "status IN (0, 1, 5, 6)",
              name: "idx_active_provisioning_job_per_project"
  end
end
