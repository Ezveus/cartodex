module Admin
  module Decks
    class IndexView < ApplicationComponent
      def initialize(decks:)
        @decks = decks
      end

      def view_template
        div(class: "admin-container") do
          h1 { "Decks" }

          render Ui::AdminTable.new(columns: %w[Name Owner Cards Created]) do
            @decks.each do |deck|
              tr do
                td { link_to deck.name, helpers.admin_deck_path(deck) }
                td { deck.user.email }
                td { deck.deck_cards.sum(&:quantity).to_s }
                td { deck.created_at.strftime("%Y-%m-%d") }
              end
            end
          end
        end
      end
    end
  end
end
