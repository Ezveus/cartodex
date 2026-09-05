# frozen_string_literal: true

module Ui
  # The admin panel's navbar. Same chrome as the other two — through Ui::NavbarShell, which is
  # where the hamburger and the `navbar` Stimulus wiring live — with its own brand label and an
  # extra `admin-navbar` class for the dark treatment.
  class AdminNavbar < ApplicationComponent
    include Ui::NavLinks

    def initialize(current_user:, active_section:)
      @current_user = current_user
      @active_section = active_section
    end

    def view_template
      # No search trigger: Layouts::AdminLayout renders neither the overlay nor the
      # search-overlay controller that would answer the click.
      render Ui::NavbarShell.new(
        brand_path: admin_root_path, brand_label: "Cartodex Admin", nav_class: "admin-navbar",
        search: false
      ) do
        nav_links
        right_section
      end
    end

    private

    def nav_links
      div(class: "navbar-links") do
        nav_link "Dashboard", admin_root_path, "dashboard"
        nav_link "Card Sets", admin_card_sets_path, "card_sets"
        nav_link "Cards", admin_cards_path, "cards"
        nav_link "Users", admin_users_path, "users"
        nav_link "Decks", admin_decks_path, "decks"
        nav_link "Archetypes", admin_archetypes_path, "archetypes"
        nav_link "Standard Pools", admin_standard_pools_path, "standard_pools"
        nav_link "Imports", admin_imports_path, "imports"
        nav_link "Limitless import", new_admin_standings_import_path, "standings_imports"
        link_to "Jobs", mission_control_jobs_path, class: "navbar-link"
      end
    end

    def right_section
      div(class: "navbar-right") do
        span(class: "navbar-user") { @current_user.email }
        link_to "Back to app", dashboard_path, class: "navbar-link"
        link_to "Sign out", destroy_user_session_path, data: { turbo_method: :delete }, class: "navbar-link"
      end
    end
  end
end
