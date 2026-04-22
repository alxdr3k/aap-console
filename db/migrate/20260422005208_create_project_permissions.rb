class CreateProjectPermissions < ActiveRecord::Migration[8.1]
  def change
    create_table :project_permissions do |t|
      # index: false to avoid duplicate — composite unique index covers lookups
      t.references :org_membership, null: false, foreign_key: true, index: false
      t.references :project, null: false, foreign_key: true, index: false
      t.string :role, null: false, default: "read"

      t.timestamps
    end

    add_index :project_permissions, [ :org_membership_id, :project_id ], unique: true
    add_index :project_permissions, :project_id
  end
end
