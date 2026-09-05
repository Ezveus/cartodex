Rails.application.routes.draw do
  devise_for :users
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # MCP server — authenticated by per-user API token (Authorization: Bearer),
  # so it lives outside the Devise session-authenticated block.
  match "mcp", to: "mcp/server#handle", via: %i[get post delete]

  # OAuth 2.1 authorization server. Outside the Devise `authenticate` block:
  # Doorkeeper redirects to sign-in itself through resource_owner_authenticator,
  # and wrapping it would break the return path.
  #
  # The applications and authorized_applications controllers are skipped: clients
  # are created by dynamic registration (Oauth::RegistrationsController), and the
  # user-facing list of connected apps is a Phlex section of /settings.
  use_doorkeeper do
    controllers authorizations: "oauth/authorizations", tokens: "oauth/tokens"
    skip_controllers :applications, :authorized_applications
  end

  # Discovery documents. Public by necessity: a client reads them before it has
  # any credential. The protected-resource document answers at two paths — see
  # the controller for why.
  get ".well-known/oauth-authorization-server", to: "oauth/metadata#authorization_server"
  get ".well-known/oauth-protected-resource",     to: "oauth/metadata#protected_resource"
  get ".well-known/oauth-protected-resource/mcp", to: "oauth/metadata#protected_resource"

  # RFC 7591 dynamic client registration. Unauthenticated by necessity — see
  # Oauth::ClientRegistrar for why the redirect-URI allowlist is what keeps
  # this endpoint safe.
  post "oauth/register", to: "oauth/registrations#create"

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in Layouts::ApplicationLayout)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Outside `authenticate :user`: these controllers straddle the session boundary and gate
  # themselves through PubliclyReachable. Note that `resources :decks` carries its nested
  # deck_results routes out with it — DeckResultsController deliberately does not include the
  # concern and keeps ApplicationController's before_action as its only gate.
  get "dashboard", to: "home#dashboard"
  get "search", to: "search#show"

  resources :decks, only: [ :index, :show, :new, :create, :edit, :update, :destroy ] do
    get :matchups, on: :collection
    get :compare, on: :collection
    get :shared, on: :collection
    get :export, on: :member
    get :stats, on: :member
    post :duplicate, on: :member
    patch :share, on: :member
    resources :deck_results, only: [ :index, :edit, :update, :destroy ]
  end

  resources :cards, only: [ :index, :show ] do
    get :image, on: :member
  end

  # index and show only; the rest of the resource, and every nested entry route, gates itself
  # through Devise. The entry routes ride out of `authenticate :user` by nesting alone, the
  # same way deck_results do under decks.
  resources :tournaments do
    # Declared before the member routes are emitted, so /tournaments/mine is not swallowed
    # by /tournaments/:id.
    get :mine, on: :collection
    # `resources :entries`, not `:tournament_entries`: the URL reads
    # /tournaments/:tournament_id/entries/:id. The cost is that polymorphic form_with cannot
    # derive the path from the TournamentEntry class name, so the entry forms pass an
    # explicit `url:` — see Tournaments::Entries::Form.
    resources :entries, only: %i[new create show edit update destroy],
              controller: "tournaments/entries" do
      member do
        post :attach_results
        delete :detach_result
      end
    end

    # `resources :standings`, not `:tournament_standings`: the URL reads
    # /tournaments/:tournament_id/standings/:id, the same call the entries block makes — and with
    # the same cost, that polymorphic form_with cannot derive the path from the TournamentStanding
    # class name, so the standings form passes an explicit `url:`.
    #
    # No show and no index: the sheet lives inside tournaments#show, and a row is six fields —
    # the call Admin::StandardPoolsController makes for a five-field pool.
    #
    # These routes leave the app-wide `authenticate :user` block by nesting alone, exactly as
    # entries do. Tournaments::StandingsController keeps authenticate_user! as its only gate.
    resources :standings, only: %i[new create edit update destroy],
              controller: "tournaments/standings" do
      member do
        post :claim
        delete :unclaim
      end
    end
  end

  # Authenticated routes
  authenticate :user do
    resource :settings, only: [ :show ]
    resource :mcp_token, only: [ :create, :destroy ]
    resources :connected_apps, only: [ :destroy ]

    # Living design-system reference. Not exposed in production.
    get "styleguide", to: "styleguide#show" unless Rails.env.production?
    resources :collections, only: [ :index ]
    resources :over_allocations, only: [ :index ] do
      post :reallocate, on: :collection
    end
    resources :tournament_profiles, except: [ :show ]

    # Member-only for now. Moving this resource out of the `authenticate :user` block is the first
    # of the edits that open the two pages to visitors; the rest — and the four nothing would ask
    # for, which no test would go red over — are listed above ArchetypesController.
    resources :archetypes, only: [ :index, :show ]

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
        post :undo, on: :member
      end
      resources :archetypes
      # No show action: a pool is five fields and the index already lists all of
      # them, so a show page would only restate the row.
      resources :standard_pools, except: [ :show ]

      # Importing an archetype's field off Limitless TCG. `preview` is a GET on the collection
      # and not the POST a "run this" button suggests: Turbo treats a non-redirected 200
      # answering a form POST as an error, so a POST that rendered the plan would do nothing at
      # all in a browser — and a plan reached by GET is reload-safe and bookmarkable besides.
      #
      # `destroy` takes an *Import* id, not a standings-import id: there is no such record. It is
      # the "undo this run" action, and the receipt it undoes is the Import row.
      resources :standings_imports, only: [ :new, :create ] do
        get :preview, on: :collection
      end
    end

    # API endpoints
    namespace :api do
      resources :archetypes, only: [ :index, :create ]
      resources :cards, only: [ :index ]
      resources :collections, only: [ :index, :create, :update, :destroy ]
      resources :decks do
        post :import, on: :collection
        get :suggested_archetype, on: :member
        resources :cards, only: [ :index, :create, :update, :destroy ], controller: "deck_cards" do
          # Swapping a slot to another printing changes the very id that identifies it, so it
          # gets its own action rather than another branch in deck_cards#update.
          resources :printings, only: [ :index ], controller: "deck_card_printings"
          resource :printing, only: [ :update ], controller: "deck_card_printings"
        end
        resources :results, only: [ :create ], controller: "deck_results"
      end
    end
  end

  # Root path
  # The visitor dashboard carries the Sign in / Sign up buttons, so the old welcome page said
  # nothing the dashboard does not. `/dashboard` stays alongside it: the navbar brand and
  # existing bookmarks name it, and two routes onto one action cost nothing.
  root "home#dashboard"
end
