module Decks
  module Odds
    # An N other than 60 is not an edge case to tolerate but the normal state of a deck under
    # construction, which is when this page is most useful. The numbers are computed against the real
    # N; this names the gap so nobody compares them against a table they read somewhere else.
    class DeckSizeNotice < ApplicationComponent
      def initialize(report:)
        @report = report
      end

      def view_template
        return if @report.reference_size?

        div(class: "odds-notice") do
          p do
            # Deliberately not possessive: page_view_test.rb asserts on this sentence, and Phlex
            # escapes an apostrophe to &#39;, which no plain `assert_includes` on the body would match.
            plain "These odds are computed against the #{@report.deck_size} cards in this deck, " \
                  "not against 60. They will move as the list fills out."
          end
        end
      end
    end
  end
end
