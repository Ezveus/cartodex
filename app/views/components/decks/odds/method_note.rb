module Decks
  module Odds
    # Five limits of the model, stated on the page rather than left to be discovered.
    #
    # The second is the one a player would otherwise never guess, and it is stated in the direction
    # of the error: Iono and Lillie's Determination shuffle the hand back in, so already-seen cards
    # become drawable again and the true chance of having seen a given card is *lower* than this page
    # says. Professor's Research discards instead, and is exact.
    class MethodNote < ApplicationComponent
      NOTES = [
        "Draw effects are not modelled. The scenario controls are the only way draw enters this " \
          "page — nothing infers that the deck plays Professor's Research, and the manual input is " \
          "the admission.",
        "Iono and Lillie's Determination are approximated upward. Drawing off the top is exactly " \
          "\"more cards in the prefix\"; shuffling the hand back in and redrawing is not, because " \
          "already-seen cards become drawable again. Professor's Research, which discards rather " \
          "than shuffles, is exact.",
        "\"Seen\" is not \"held\". A card reached and then discarded counts as seen, which matters " \
          "most to the combination calculator: it answers \"I have seen one of each\", not \"I hold " \
          "them at the same time\".",
        "Opponent mulligans are not modelled. They hand out extra cards, and how many depends on " \
          "the other deck.",
        "The two prize columns answer a different question from every other number here. " \
          "Accessibility is conditional on a keepable opening hand; prize risk is not, because " \
          "where your copies sit is a fact about the deal that happened rather than about the " \
          "deals that were thrown away. The hand and the prizes come off one deck, so the two " \
          "measures do differ — by a few hundredths of a point at 60 cards, upward for a Basic " \
          "Pokemon and downward for anything else."
      ].freeze

      def view_template
        section(class: "odds-panel odds-method") do
          h2 { "What this page does not model" }
          ul { NOTES.each { |note| li { note } } }
          p(class: "odds-note") do
            plain "Every number here is exact and closed-form. Nothing is simulated and nothing is " \
                  "sampled."
          end
        end
      end
    end
  end
end
