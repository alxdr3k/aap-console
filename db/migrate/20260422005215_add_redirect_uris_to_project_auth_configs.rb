class AddRedirectUrisToProjectAuthConfigs < ActiveRecord::Migration[8.1]
  def change
    add_column :project_auth_configs, :redirect_uris, :json
    add_column :project_auth_configs, :post_logout_redirect_uris, :json
  end
end
