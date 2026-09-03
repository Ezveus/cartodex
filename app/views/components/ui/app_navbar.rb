# frozen_string_literal: true

module Ui
  class AppNavbar < ApplicationComponent
    include Ui::NavLinks

    def initialize(current_user:, active_section:)
      @current_user = current_user
      @active_section = active_section
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
        # query — the visitor navigated the app better than the member. The two entries name
        # different sections, so /decks and a deck's own page light this one and /decks/shared
        # lights the next (see Ui::NavLinks.section_for).
        nav_link "Shared decks", shared_decks_path, "shared_decks"
        nav_link "Tournaments", tournaments_path, "tournaments"
        # "entries" is Tournaments::EntriesController's own controller_name (nested resources
        # are named after the model, TournamentEntry, but the controller_name it reports is the
        # route segment); a participation's own show/new/edit pages have no entry of their own,
        # so they light the list they hang off, same as a deck's own page lights "Decks".
        nav_link "My tournaments", mine_tournaments_path, "my_tournaments", "entries"
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
