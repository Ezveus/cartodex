# frozen_string_literal: true

module Ui
  # The navbar a signed-in member gets. Four top-level entries and an account menu, where there
  # used to be nine links plus an email and three account links — measured, that row needed 1430px
  # of incompressible width inside a 1232px container and overflowed the document at every viewport
  # below ~1660px (661px of it at 769px). See
  # docs/superpowers/specs/2026-09-08-grouped-navigation-design.md.
  class AppNavbar < ApplicationComponent
    include Ui::NavLinks

    def initialize(current_user:, active_section:)
      @current_user = current_user
      @active_section = active_section
    end

    def view_template
      # Dashboard has no entry of its own any more: the brand already pointed there, and it is the
      # one destination a logo can plausibly carry.
      render Ui::NavbarShell.new(brand_path: dashboard_path, brand_active: @active_section == "home") do
        nav_links
        account_menu
      end
    end

    private

    def nav_links
      div(class: "navbar-links") do
        # A member had no way to reach the shared index other than typing a matching search query —
        # the visitor navigated the app better than the member. The two entries name different
        # sections, so /decks and a deck's own page light the first and /decks/shared the second
        # (see Ui::NavLinks.section_for).
        nav_group "Decks", "decks",
          [ "My decks", decks_path, %w[decks] ],
          [ "Shared decks", shared_decks_path, %w[shared_decks] ],
          [ "Collection", collections_path, %w[collections] ]
        # "entries" is Tournaments::EntriesController's own controller_name (nested resources are
        # named after the model, TournamentEntry, but the controller_name it reports is the route
        # segment); a participation's own show/new/edit pages have no entry of their own, so they
        # light the list they hang off, same as a deck's own page lights "My decks".
        nav_group "Tournaments", "tournaments",
          [ "All tournaments", tournaments_path, %w[tournaments] ],
          [ "My tournaments", mine_tournaments_path, %w[my_tournaments entries] ],
          [ "Profiles", tournament_profiles_path, %w[tournament_profiles] ]
        nav_link "Cards", cards_path, "cards"
        # Ui::PublicNavbar carries this entry too, since /archetypes went public — it used to be
        # the one member link a visitor's navbar deliberately withheld, a link into a sign-in wall
        # being worse than no link. "archetypes" is ArchetypesController's own controller_name, so
        # Ui::NavLinks.section_for resolves it with no SECTION_OVERRIDES row. Admin::ArchetypesController
        # reports that same controller_name and Ui::AdminNavbar already lights an entry on it, which
        # is not a collision: the two navbars are never rendered on the same page
        # (Layouts::AdminLayout vs Layouts::ApplicationLayout). NavbarActiveSectionTest holds both
        # halves of that down.
        nav_link "Archetypes", archetypes_path, "archetypes"
      end
    end

    # The email is the single widest incompressible item the old row carried — one unbreakable word
    # that no amount of flex shrinking could narrow — so it moves inside the panel rather than
    # merely being shortened. The group lights nothing: none of these pages is a nav section, and
    # Settings sitting lit on /settings would be a fifth thing competing with the four that matter.
    def account_menu
      div(class: "navbar-account") do
        render Ui::NavGroup.new(
          label: "Account", id: "account", initial: @current_user.email.first.upcase, align: :right
        ) do
          span(class: "navbar-user") { @current_user.email }
          link_to "Settings", settings_path, class: "navbar-link"
          link_to "Admin", admin_root_path, class: "navbar-link" if @current_user.admin?
          link_to "Sign out", destroy_user_session_path, data: { turbo_method: :delete }, class: "navbar-link"
        end
      end
    end
  end
end
