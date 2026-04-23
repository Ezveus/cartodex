# frozen_string_literal: true

module Ui
  class AppNavbar < ApplicationComponent
    def initialize(current_user:, active_controller:)
      @current_user = current_user
      @active_controller = active_controller
    end

    def view_template
      nav(class: "navbar", data: { controller: "navbar" }) do
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
      link_to "Cartodex", dashboard_path, class: "navbar-brand"
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
        nav_link "Dashboard", dashboard_path, "home"
        nav_link "Decks", decks_path, "decks"
        nav_link "Cards", cards_path, "cards"
        nav_link "Collection", "#", "collections"
        nav_link "Profiles", tournament_profiles_path, "tournament_profiles"
      end
    end

    def right_section
      div(class: "navbar-right") do
        span(class: "navbar-user") { @current_user.email }
        link_to "Admin", admin_root_path, class: "navbar-link" if @current_user.admin?
        link_to "Sign out", destroy_user_session_path, data: { turbo_method: :delete }, class: "navbar-link"
      end
    end

    def nav_link(label, path, controller)
      link_to label, path, class: [ "navbar-link", ("active" if @active_controller == controller) ].compact.join(" ")
    end
  end
end
