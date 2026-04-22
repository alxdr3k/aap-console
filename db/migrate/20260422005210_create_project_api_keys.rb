class CreateProjectApiKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :project_api_keys do |t|
      t.references :project, null: false, foreign_key: true, index: false
      t.string :name, null: false
      t.string :token_digest, null: false
      t.string :token_prefix, null: false
      t.datetime :last_used_at
      t.datetime :revoked_at

      t.timestamps
    end

    add_index :project_api_keys, [ :project_id, :name ], unique: true
    add_index :project_api_keys, :token_digest, unique: true
    add_index :project_api_keys, :project_id
  end
end
