Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # Auth
  get  "auth/keycloak/callback", to: "sessions#create"
  get  "auth/failure",           to: "sessions#failure"
  delete "auth/logout",          to: "sessions#destroy"

  # User search (Keycloak proxy)
  get "users/search", to: "users#search"

  # Organizations and nested resources
  resources :organizations, param: :slug do
    resources :members, param: :user_sub, only: [ :index, :create, :update, :destroy ]

    resources :projects, param: :slug do
      resource  :auth_config,    only: [ :show, :update ]
      resource  :litellm_config, only: [ :show, :update ]
      resources :config_versions, only: [ :index ]
    end
  end

  # Provisioning jobs (global, not nested)
  resources :provisioning_jobs, only: [ :show ] do
    member do
      post :retry
      get  :secrets
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
    end
  end

  root to: redirect("/organizations")
end
