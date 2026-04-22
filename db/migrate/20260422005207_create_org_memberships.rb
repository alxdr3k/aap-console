class CreateOrgMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :org_memberships do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :user_sub, null: false
      t.string :role, null: false, default: "read"
      t.datetime :invited_at
      t.datetime :joined_at

      t.timestamps
    end

    add_index :org_memberships, [ :organization_id, :user_sub ], unique: true
    add_index :org_memberships, :user_sub
  end
end
