module Ui
  # The navbar a visitor gets. Same chrome as Ui::AppNavbar, different links.
  class PublicNavbar < ApplicationComponent
    def initialize(active_controller:)
      @active_controller = active_controller
    end

    def view_template
      render Ui::NavbarShell.new(brand_path: root_path) do
        div(class: "navbar-links") do
          nav_link "Cards", cards_path, "cards"
          nav_link "Shared decks", shared_decks_path, "decks"
        end
        div(class: "navbar-right") do
          link_to "Sign in", new_user_session_path, class: "navbar-link"
          link_to "Sign up", new_user_registration_path, class: "navbar-link"
        end
      end
    end

    private

    def nav_link(label, path, controller)
      link_to label, path, class: [ "navbar-link", ("active" if @active_controller == controller) ].compact.join(" ")
    end
  end
end
