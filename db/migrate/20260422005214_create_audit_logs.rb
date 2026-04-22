class CreateAuditLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_logs do |t|
      # organization/project are nullable to survive org/project deletion
      t.references :organization, null: true, foreign_key: true, index: false
      t.references :project, null: true, foreign_key: true, index: false
      t.string :user_sub, null: false
      t.string :action, null: false
      t.string :resource_type, null: false
      t.string :resource_id
      t.json :details

      t.timestamps
    end

    add_index :audit_logs, [ :organization_id, :created_at ]
    add_index :audit_logs, [ :project_id, :created_at ]
    add_index :audit_logs, :created_at
  end
end
