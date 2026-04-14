# frozen_string_literal: true

module Ui
  class AdminNavbar < ApplicationComponent
    def initialize(current_user:, active_controller:)
      @current_user = current_user
      @active_controller = active_controller
    end

    def view_template
      nav(class: "navbar admin-navbar", data: { controller: "navbar" }) do
        div(class: "navbar-inner") do
          brand
          hamburger_button
          div(class: "navbar-menu", data: { navbar_target: "menu" }) do
            nav_links
            right_section
          end
        end
      end
    end

    private

    def brand
      link_to "Cartodex Admin", helpers.admin_root_path, class: "navbar-brand"
    end

    def hamburger_button
      button(
        class: "navbar-toggle",
        data: { action: "navbar#toggle" },
        aria: { label: "Menu", expanded: "false" }
      ) do
        span(class: "navbar-toggle-icon")
      end
    end

    def nav_links
      div(class: "navbar-links") do
        nav_link "Dashboard", helpers.admin_root_path, "dashboard"
        nav_link "Card Sets", helpers.admin_card_sets_path, "card_sets"
        nav_link "Cards", helpers.admin_cards_path, "cards"
        nav_link "Users", helpers.admin_users_path, "users"
        nav_link "Decks", helpers.admin_decks_path, "decks"
        nav_link "Archetypes", helpers.admin_archetypes_path, "archetypes"
        nav_link "Imports", helpers.admin_imports_path, "imports"
        link_to "Jobs", helpers.mission_control_jobs_path, class: "navbar-link"
      end
    end

    def right_section
      div(class: "navbar-right") do
        span(class: "navbar-user") { @current_user.email }
        link_to "Back to app", helpers.dashboard_path, class: "navbar-link"
        link_to "Sign out", helpers.destroy_user_session_path, data: { turbo_method: :delete }, class: "navbar-link"
      end
    end

    def nav_link(label, path, controller)
      link_to label, path, class: [ "navbar-link", ("active" if @active_controller == controller) ].compact.join(" ")
    end
  end
end
