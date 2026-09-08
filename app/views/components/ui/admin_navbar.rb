# frozen_string_literal: true

module Ui
  # The admin panel's navbar. Same chrome as the other two — through Ui::NavbarShell, which is
  # where the hamburger and the `navbar` Stimulus wiring live — with its own brand label and an
  # extra `admin-navbar` class for the dark treatment.
  #
  # It overflowed worse than the member's: twelve links plus three account ones needed 1330px in a
  # 1232px container, ran 561px off the document at 769px, and wrapped its labels to three lines
  # inside a 56px band. Three groups now.
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
        brand_path: admin_root_path, brand_label: "Cartodex Admin",
        # Admin::DashboardController's own controller_name, not "home" — the admin panel's front
        # page is a different section from the app's.
        brand_active: @active_section == "dashboard",
        nav_class: "admin-navbar", search: false
      ) do
        nav_links
        account_menu
      end
    end

    private

    def nav_links
      div(class: "navbar-links") do
        # Split by what the row *is*: the printed card catalogue and the vocabulary applied to it;
        # the records members create; and the machinery that pulls both in.
        nav_group "Catalog", "catalog",
          [ "Card Sets", admin_card_sets_path, %w[card_sets] ],
          [ "Cards", admin_cards_path, %w[cards] ],
          [ "Card Labels", admin_card_labels_path, %w[card_labels] ],
          [ "Card Roles", admin_card_roles_path, %w[card_roles] ]
        nav_group "Content", "content",
          [ "Users", admin_users_path, %w[users] ],
          [ "Decks", admin_decks_path, %w[decks] ],
          [ "Archetypes", admin_archetypes_path, %w[archetypes] ],
          [ "Standard Pools", admin_standard_pools_path, %w[standard_pools] ]
        nav_group "Imports", "imports",
          [ "Imports", admin_imports_path, %w[imports] ],
          [ "Limitless import", new_admin_standings_import_path, %w[standings_imports] ],
          # Mission Control is mounted, not routed through this app's controllers, so it belongs to
          # no nav section and must never light its group. Ui::NavGroup reads an empty list as
          # "matches nothing" rather than as "matches anything", which is what makes that safe.
          [ "Jobs", mission_control_jobs_path, [] ]
      end
    end

    def account_menu
      div(class: "navbar-account") do
        render Ui::NavGroup.new(
          label: "Account", id: "account", initial: @current_user.email.first.upcase, align: :right
        ) do
          span(class: "navbar-user") { @current_user.email }
          link_to "Back to app", dashboard_path, class: "navbar-link"
          link_to "Sign out", destroy_user_session_path, data: { turbo_method: :delete }, class: "navbar-link"
        end
      end
    end
  end
end
