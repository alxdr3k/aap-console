class CreateProvisioningSteps < ActiveRecord::Migration[8.1]
  def change
    create_table :provisioning_steps do |t|
      t.references :provisioning_job, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :step_order, null: false
      t.integer :status, null: false, default: 0
      t.datetime :started_at
      t.datetime :completed_at
      t.text :error_message
      t.integer :retry_count, default: 0
      t.integer :max_retries, default: 3
      t.json :result_snapshot

      t.timestamps
    end

    add_index :provisioning_steps, [ :provisioning_job_id, :step_order ]
  end
end
