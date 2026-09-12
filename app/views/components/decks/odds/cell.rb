module Decks
  module Odds
    # One number the scenario controls move.
    #
    # The whole curve ships in the attribute and deck_odds_controller.js picks an index out of it:
    # `seen` (turn + effect draws + prizes taken) for an accessibility cell, prizes taken alone for a
    # prize cell — which is a question about the prize block itself rather than about accessibility,
    # and is why that axis exists at all. The controller computes nothing: the repo has no JS test
    # infrastructure, so a second implementation of the conditional hypergeometric would be held down
    # by nothing whatsoever.
    #
    # Measured payload for a 60-card deck: about 9 KB of data-curve attributes.
    class Cell < ApplicationComponent
      include Formatting

      TARGETS = { seen: "cell", prizes: "prizeCell" }.freeze

      def initialize(curve:, index:, axis: :seen)
        @curve = curve
        @index = index
        @axis = axis
      end

      def view_template
        span(class: "odds-value",
             data: { deck_odds_target: TARGETS.fetch(@axis), curve: @curve.to_json }) do
          percent(@curve[@index] || @curve.last)
        end
      end
    end
  end
end
