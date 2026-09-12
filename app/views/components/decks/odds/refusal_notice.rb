module Decks
  module Odds
    # The page naming its own incapacity rather than printing a number. Two states reach here, and
    # both are reachable from the UI rather than theoretical: a deck of 60 Trainers, and every deck
    # in the minute after it is created.
    class RefusalNotice < ApplicationComponent
      def initialize(report:)
        @report = report
      end

      def view_template
        div(class: "odds-refusal") { p { message } }
      end

      private

      # Size before Basics, and that order is the whole of what page_view_test.rb pins here. A deck
      # holding nothing at all satisfies both conditions, and "this deck holds no Basic Pokémon"
      # sends the reader who just clicked New deck looking for the wrong thing entirely.
      def message
        if @report.deck_size < @report.hand_size
          "This deck holds #{@report.deck_size} cards — too few to deal an opening hand and six " \
            "prizes. Add cards and the odds will appear."
        else
          "This deck holds no Basic Pokémon, so it cannot start a game. " \
            "Every number on this page is conditional on a keepable opening hand, and there is none."
        end
      end
    end
  end
end
