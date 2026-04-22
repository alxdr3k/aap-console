class CreateConfigVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :config_versions do |t|
      t.references :project, null: false, foreign_key: true
      # provisioning_job is optional (manual rollbacks may not have a job)
      t.references :provisioning_job, null: true, foreign_key: true, index: false
      t.string :version_id, null: false
      t.string :change_type, null: false
      t.text :change_summary
      t.string :changed_by_sub, null: false
      t.json :snapshot

      t.timestamps
    end

    add_index :config_versions, [ :project_id, :created_at ]
    add_index :config_versions, :provisioning_job_id
  end
end
