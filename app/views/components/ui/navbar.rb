module Ui
  class Navbar < ApplicationComponent
    def initialize(variant:, current_user:, active_controller:)
      @variant = variant
      @current_user = current_user
      @active_controller = active_controller
    end

    def view_template
      nav(class: [ "navbar", ("admin-navbar" if @variant == :admin) ].compact.join(" ")) do
        div(class: "navbar-inner") do
          brand
          nav_links
          right_section
        end
      end
    end

    private

    def brand
      if @variant == :admin
        link_to "Cartodex Admin", helpers.admin_root_path, class: "navbar-brand"
      else
        link_to "Cartodex", helpers.dashboard_path, class: "navbar-brand"
      end
    end

    def nav_links
      div(class: "navbar-links") do
        if @variant == :admin
          nav_link "Dashboard", helpers.admin_root_path, "dashboard"
          nav_link "Card Sets", helpers.admin_card_sets_path, "card_sets"
          nav_link "Cards", helpers.admin_cards_path, "cards"
          nav_link "Users", helpers.admin_users_path, "users"
          nav_link "Decks", helpers.admin_decks_path, "decks"
          link_to "Jobs", helpers.mission_control_jobs_path, class: "navbar-link"
        else
          nav_link "Dashboard", helpers.dashboard_path, "home"
          nav_link "Decks", helpers.decks_path, "decks"
          nav_link "Cards", helpers.cards_path, "cards"
          nav_link "Collection", "#", "collections"
        end
      end
    end

    def right_section
      div(class: "navbar-right") do
        span(class: "navbar-user") { @current_user.email }
        if @variant == :admin
          link_to "Back to app", helpers.dashboard_path, class: "navbar-link"
        elsif @current_user.admin?
          link_to "Admin", helpers.admin_root_path, class: "navbar-link"
        end
        link_to "Sign out", helpers.destroy_user_session_path, data: { turbo_method: :delete }, class: "navbar-link"
      end
    end

    def nav_link(label, path, controller)
      link_to label, path, class: [ "navbar-link", ("active" if @active_controller == controller) ].compact.join(" ")
    end
  end
end
