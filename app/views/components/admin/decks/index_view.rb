module Admin
  module Decks
    class IndexView < ApplicationComponent
      def initialize(decks:)
        @decks = decks
      end

      def view_template
        div(class: "admin-container") do
          h1 { "Decks" }

          render Ui::DataTable.new(columns: %w[Name Owner Cards Created]) do |t|
            @decks.each do |deck|
              t.row do
                t.cell { link_to deck.name, helpers.admin_deck_path(deck) }
                t.cell { deck.user.email }
                t.cell { deck.deck_cards.sum(&:quantity).to_s }
                t.cell { deck.created_at.strftime("%Y-%m-%d") }
              end
            end
          end
        end
      end
    end
  end
end
