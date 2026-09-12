module Decks
  module Odds
    # The headline. Nothing here reacts to the controls: a mulligan happens before the first draw.
    class OpeningPanel < ApplicationComponent
      include Formatting

      def initialize(report:)
        @report = report
      end

      def view_template
        section(class: "odds-panel") do
          h2 { "Opening" }
          div(class: "deck-show-stats") do
            render Ui::Stat.new(value: percent(@report.mulligan_rate_percent), label: "mulligan rate")
            # Kernel.format for the reason Decks::Odds::Formatting spells it that way.
            render Ui::Stat.new(value: Kernel.format("%.3f", @report.mean_mulligans),
                                label: "mean mulligans")
            render Ui::Stat.new(value: @report.basics, label: "Basic Pokémon")
          end
        end
      end
    end
  end
end
