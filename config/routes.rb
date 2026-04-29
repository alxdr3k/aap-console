Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # Auth
  get  "auth/keycloak/callback", to: "sessions#create"
  get  "auth/failure",           to: "sessions#failure"
  delete "auth/logout",          to: "sessions#destroy", as: :logout

  # User search (Keycloak proxy)
  get "users/search", to: "users#search"

  # Organizations and nested resources
  resources :organizations, param: :slug do
    post "members/:user_sub/project_permissions",
         to: "member_project_permissions#create",
         as: :member_project_permissions
    patch "members/:user_sub/project_permissions/:project_slug",
          to: "member_project_permissions#update",
          as: :member_project_permission
    delete "members/:user_sub/project_permissions/:project_slug",
           to: "member_project_permissions#destroy"

    resources :members, param: :user_sub, only: [ :index, :create, :update, :destroy ]

    resources :projects, param: :slug, only: [ :index, :new, :create, :show, :update, :destroy ] do
      resource  :auth_config,    only: [ :show, :update ]
      resource  :litellm_config, only: [ :show, :update ]
      resources :config_versions, only: [ :index ]
      resources :project_api_keys, only: [ :index, :create, :destroy ]
    end
  end

  # Provisioning jobs (global, not nested)
  resources :provisioning_jobs, only: [ :show ] do
    member do
      post :retry
      get  :secrets
      get "steps/:step_id", action: :step, as: :step
    end
  end

  # Config versions (rollback)
  resources :config_versions, only: [ :show ] do
    post :rollback, on: :member
  end

  # Config Server App Registry API
  namespace :api do
    namespace :v1 do
      resources :apps, only: [ :index ]
      post "project_api_keys/verify", to: "project_api_keys#verify"
    end
  end

  root to: redirect("/organizations")
end
