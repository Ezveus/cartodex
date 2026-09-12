module Decks
  module Odds
    # One compact row, three steppers feeding one integer, with the integer shown.
    #
    # `d` and `p` are mathematically interchangeable — they enter every formula through their sum
    # alone — so folding them into one "+X cards gained" control would give identical numbers. They
    # are kept apart for two reasons. Their ceilings differ (p <= 6, d <= N - 13) and a merged
    # control could clamp neither correctly. And the prize panel's whole point is a sentence a merged
    # control makes unsayable: a one-of ACE SPEC is 10.00 % unreachable at zero prizes taken, 5.00 %
    # at three, and 0 % at six.
    #
    # "Turn N is N draws": since Sun & Moon both players draw on their first turn, only the attack is
    # withheld from the player going first — so there is no first/second control, because there is no
    # first/second difference to model.
    #
    # The printed total is the honest line: it is literally the number that enters the formula.
    class ScenarioControls < ApplicationComponent
      def initialize(report:)
        @report = report
      end

      def view_template
        div(class: "odds-scenario") do
          stepper("turn", "Turn", Report::DEFAULT_TURN, 1, [ @report.max_draws, 1 ].max)
          stepper("effectDraws", "+ effect draws", 0, 0, @report.max_draws)
          stepper("prizesTaken", "Prizes taken", 0, 0, @report.prize_count) if @report.prizes?

          p(class: "odds-scenario-summary") do
            plain "→ "
            span(data: { deck_odds_target: "seenSummary" }) { summary }
          end
        end
      end

      private

      # String values, never Symbols: Phlex dasherises a Symbol attribute *value*, and every name
      # below is matched verbatim by Stimulus.
      def stepper(field, label, value, min, max)
        div(class: "odds-stepper") do
          span(class: "odds-stepper-label") { label }
          step_button(field, -1, "#{label}: one less", "−")
          input(type: "number", class: "form-input odds-stepper-input",
                value: value, min: min, max: max, aria_label: label,
                data: { deck_odds_target: field, action: "input->deck-odds#render" })
          step_button(field, 1, "#{label}: one more", "+")
        end
      end

      def step_button(field, delta, label, glyph)
        button(type: "button", class: "btn btn-secondary btn-sm", aria_label: label,
               data: { action: "deck-odds#step",
                       deck_odds_field_param: field,
                       deck_odds_delta_param: delta }) { glyph }
      end

      # What deck_odds_controller.js rewrites this span to on connect. Spelled here too so the line
      # is right for the instant before Stimulus boots, and with no session at all.
      def summary
        drawn = [ Report::DEFAULT_TURN, @report.max_draws ].min

        "#{@report.hand_size + drawn} cards seen (#{@report.hand_size} hand + #{drawn} drawn + 0 prizes)"
      end
    end
  end
end
