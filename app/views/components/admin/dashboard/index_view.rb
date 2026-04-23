module Admin
  module Dashboard
    class IndexView < ApplicationComponent
      def initialize(user_count:, card_count:, set_count:, deck_count:, recent_users:, recent_decks:)
        @user_count = user_count
        @card_count = card_count
        @set_count = set_count
        @deck_count = deck_count
        @recent_users = recent_users
        @recent_decks = recent_decks
      end

      def view_template
        div(class: "admin-container") do
          h1 { "Dashboard" }
          stats_grid
          div(class: "admin-grid-2col") do
            recent_users_table
            recent_decks_table
          end
        end
      end

      private

      def stats_grid
        div(class: "admin-stats-grid") do
          render Ui::Stat.new(value: @user_count, label: "Users", variant: :admin)
          render Ui::Stat.new(value: @card_count, label: "Cards", variant: :admin)
          render Ui::Stat.new(value: @set_count, label: "Sets", variant: :admin)
          render Ui::Stat.new(value: @deck_count, label: "Decks", variant: :admin)
        end
      end

      def recent_users_table
        div do
          h2 { "Recent Users" }
          render Ui::DataTable.new(columns: %w[Email Admin Joined]) do |t|
            @recent_users.each do |user|
              t.row do
                t.cell { user.email }
                t.cell { user.admin? ? "Yes" : "No" }
                t.cell { user.created_at.strftime("%Y-%m-%d") }
              end
            end
          end
        end
      end

      def recent_decks_table
        div do
          h2 { "Recent Decks" }
          render Ui::DataTable.new(columns: %w[Name Owner Created]) do |t|
            @recent_decks.each do |deck|
              t.row do
                t.cell { link_to deck.name, admin_deck_path(deck) }
                t.cell { deck.user.email }
                t.cell { deck.created_at.strftime("%Y-%m-%d") }
              end
            end
          end
        end
      end
    end
  end
end
