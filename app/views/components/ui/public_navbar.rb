module Ui
  # The navbar a visitor gets. Same chrome as Ui::AppNavbar, different links.
  class PublicNavbar < ApplicationComponent
    include Ui::NavLinks

    def initialize(active_section:)
      @active_section = active_section
    end

    def view_template
      render Ui::NavbarShell.new(brand_path: root_path) do
        div(class: "navbar-links") do
          nav_link "Cards", cards_path, "cards"
          nav_link "Tournaments", tournaments_path, "tournaments"
          # Both sections, unlike Ui::AppNavbar: a visitor has no "Decks" entry, so this is
          # the one a shared deck's own page has to light.
          nav_link "Shared decks", shared_decks_path, "decks", "shared_decks"
        end
        div(class: "navbar-right") do
          link_to "Sign in", new_user_session_path, class: "navbar-link"
          link_to "Sign up", new_user_registration_path, class: "navbar-link"
        end
      end
    end
  end
end
