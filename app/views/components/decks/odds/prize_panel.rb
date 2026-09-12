module Decks
  module Odds
    # The groups most likely to be sitting where they cannot be reached, most at risk first.
    #
    # The ordering *is* the panel: the per-card table below carries every group's prize columns
    # already, so this is capped rather than a second copy of it. Both columns react to the prizes
    # taken stepper alone — "still unreachable" is a question about the prize block, not about how
    # much of the deck has been seen.
    class PrizePanel < ApplicationComponent
      include Formatting

      COLUMNS = [ "Card", "Copies", "At least one prized", "All copies unreachable" ].freeze

      def initialize(report:)
        @report = report
      end

      def view_template
        return unless @report.prizes?

        section(class: "odds-panel") do
          h2 { "Prize risk" }
          render Ui::DataTable.new(columns: COLUMNS) do |t|
            @report.prize_rows.each do |row|
              t.row do
                t.cell { row.name }
                t.cell { row.copies.to_s }
                t.cell { percent(row.at_least_one_prized) }
                t.cell { render Cell.new(curve: row.all_prized_curve, index: 0, axis: :prizes) }
              end
            end
          end
          p(class: "odds-note") do
            plain "A prize is not lost — taking it puts the card in hand. The last column is the " \
                  "chance every copy is still in the prizes you have not taken."
          end
        end
      end
    end
  end
end
