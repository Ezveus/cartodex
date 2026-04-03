Rails.application.routes.draw do
  devise_for :users
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Authenticated routes
  authenticate :user do
    get 'dashboard', to: 'home#dashboard'

    # API endpoints
    namespace :api do
      resources :collections, only: [:index, :create, :update, :destroy]
      resources :decks do
        resources :cards, only: [:index, :create, :destroy], controller: 'deck_cards'
        resources :results, only: [:create], controller: 'deck_results'
      end
    end
  end

  # Root path
  root "home#welcome"
end
