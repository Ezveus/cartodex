Rails.application.routes.draw do
  devise_for :users
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # MCP server — authenticated by per-user API token (Authorization: Bearer),
  # so it lives outside the Devise session-authenticated block.
  match "mcp", to: "mcp/server#handle", via: %i[get post delete]

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in Layouts::ApplicationLayout)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Authenticated routes
  authenticate :user do
    get "dashboard", to: "home#dashboard"

    # Living design-system reference. Not exposed in production.
    get "styleguide", to: "styleguide#show" unless Rails.env.production?
    resources :decks, only: [ :index, :show, :new, :create, :edit, :update, :destroy ] do
      get :matchups, on: :collection
      get :compare, on: :collection
      get :export, on: :member
      get :stats, on: :member
      post :duplicate, on: :member
      resources :deck_results, only: [ :index, :edit, :update, :destroy ]
    end
    resources :cards, only: [ :index, :show ] do
      get :image, on: :member
    end
    resources :collections, only: [ :index ]
    resources :over_allocations, only: [ :index ]
    resources :tournament_profiles, except: [ :show ]
    resources :tournaments do
      resources :deck_results, only: [], controller: "tournaments/deck_results" do
        post :attach, on: :collection
        delete :detach, on: :member
      end
    end

    # Admin
    constraints ->(request) { request.env["warden"].user&.admin? } do
      mount MissionControl::Jobs::Engine, at: "/admin/jobs"
    end

    namespace :admin do
      root "dashboard#index"
      resources :card_sets do
        post :import, on: :collection
        post :rescrape, on: :member
      end
      resources :cards, only: [ :index, :show, :edit, :update ] do
        post :rescrape, on: :member
      end
      resources :users, only: [ :index ] do
        patch :toggle_admin, on: :member
      end
      resources :decks, only: [ :index, :show ]
      resources :imports, only: [ :index, :destroy ] do
        post :retry, on: :member
      end
      resources :archetypes
    end

    # API endpoints
    namespace :api do
      resources :archetypes, only: [ :index, :create ]
      resources :cards, only: [ :index ]
      resources :collections, only: [ :index, :create, :update, :destroy ]
      resources :decks do
        post :import, on: :collection
        get :suggested_archetype, on: :member
        resources :cards, only: [ :index, :create, :update, :destroy ], controller: "deck_cards"
        resources :results, only: [ :create ], controller: "deck_results"
      end
    end
  end

  # Root path
  root "home#welcome"
end
