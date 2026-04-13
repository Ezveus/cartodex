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
          render Ui::AdminTable.new(columns: %w[Email Admin Joined]) do
            @recent_users.each do |user|
              tr do
                td { user.email }
                td { user.admin? ? "Yes" : "No" }
                td { user.created_at.strftime("%Y-%m-%d") }
              end
            end
          end
        end
      end

      def recent_decks_table
        div do
          h2 { "Recent Decks" }
          render Ui::AdminTable.new(columns: %w[Name Owner Created]) do
            @recent_decks.each do |deck|
              tr do
                td { link_to deck.name, helpers.admin_deck_path(deck) }
                td { deck.user.email }
                td { deck.created_at.strftime("%Y-%m-%d") }
              end
            end
          end
        end
      end
    end
  end
end
