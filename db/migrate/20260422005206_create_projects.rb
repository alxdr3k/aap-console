class CreateProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :projects do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :app_id, null: false
      t.integer :status, null: false, default: 0

      t.timestamps
    end

    add_index :projects, [ :organization_id, :slug ], unique: true
    add_index :projects, :app_id, unique: true
    add_index :projects, [ :organization_id, :status ]
  end
end
