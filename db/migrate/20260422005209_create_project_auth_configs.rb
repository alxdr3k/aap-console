class CreateProjectAuthConfigs < ActiveRecord::Migration[8.1]
  def change
    create_table :project_auth_configs do |t|
      t.references :project, null: false, foreign_key: true, index: false
      t.string :auth_type, null: false
      t.string :keycloak_client_id
      t.string :keycloak_client_uuid

      t.timestamps
    end

    add_index :project_auth_configs, :project_id, unique: true
  end
end
