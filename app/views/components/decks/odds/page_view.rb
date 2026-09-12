module Decks
  module Odds
    class PageView < ApplicationComponent
      def initialize(deck:, report:, combo:)
        @deck = deck
        @report = report
        @combo = combo
      end

      def view_template
        div(class: "admin-container") do
          render Ui::PageHeader.new(title: "#{@deck.name} — Build odds") do
            link_to "Back to Deck", deck_path(@deck), class: "btn btn-secondary"
          end
        end
      end
    end
  end
end
