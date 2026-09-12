module Decks
  module Odds
    # Four limits of the model, stated on the page rather than left to be discovered.
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
          "the other deck."
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
