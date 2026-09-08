module Ui
  # The navbar a visitor gets. Same chrome as Ui::AppNavbar, different links.
  class PublicNavbar < ApplicationComponent
    include Ui::NavLinks

    def initialize(active_section:)
      @active_section = active_section
    end

    # Four links, and they stay flat: measured at 769px — the narrowest desktop width — this row
    # fits with 0px of document overflow, and it fits *because* "Shared decks" is allowed to wrap
    # to two lines. That is why `white-space: nowrap` is not applied to `.navbar-link`: it costs
    # this navbar 48px of overflow at that width, which is the defect the grouping exists to
    # remove, reintroduced on the one navbar the grouping does not touch.
    def view_template
      render Ui::NavbarShell.new(
        brand_path: root_path, brand_active: @active_section == "home", brand_destination: "Home"
      ) do
        div(class: "navbar-links") do
          nav_link "Cards", cards_path, "cards"
          nav_link "Archetypes", archetypes_path, "archetypes"
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
