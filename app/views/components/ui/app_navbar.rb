# frozen_string_literal: true

module Ui
  class AppNavbar < ApplicationComponent
    include Ui::NavLinks

    def initialize(current_user:, active_controller:)
      @current_user = current_user
      @active_controller = active_controller
    end

    def view_template
      render Ui::NavbarShell.new(brand_path: dashboard_path) do
        nav_links
        right_section
      end
    end

    private

    def nav_links
      div(class: "navbar-links") do
        nav_link "Dashboard", dashboard_path, "home"
        nav_link "Decks", decks_path, "decks"
        # A member had no way to reach the shared index other than typing a matching search
        # query — the visitor navigated the app better than the member. Both entries light up
        # on /decks/shared (see Ui::NavLinks); accepted rather than threading a finer
        # activation key through for one row.
        nav_link "Shared decks", shared_decks_path, "decks"
        nav_link "Tournaments", tournaments_path, "tournaments"
        nav_link "Cards", cards_path, "cards"
        nav_link "Collection", collections_path, "collections"
        nav_link "Profiles", tournament_profiles_path, "tournament_profiles"
      end
    end

    def right_section
      div(class: "navbar-right") do
        span(class: "navbar-user") { @current_user.email }
        link_to "Settings", settings_path, class: "navbar-link"
        link_to "Admin", admin_root_path, class: "navbar-link" if @current_user.admin?
        link_to "Sign out", destroy_user_session_path, data: { turbo_method: :delete }, class: "navbar-link"
      end
    end
  end
end
