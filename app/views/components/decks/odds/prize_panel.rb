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
            plain "#{cap_sentence}A prize is not lost — taking it puts the card in hand. The " \
                  "last column is the chance every copy is still in the prizes you have not taken."
          end
        end
      end

      private

      # Said, not merely true. The panel exists for its ordering and is capped, so on a real deck it
      # shows five of twenty-odd groups — and the cut can fall mid-tie, four groups sharing one risk
      # and two of them appearing. A reader who is not told that reads the panel as the whole answer.
      # Below the cap there is nothing to disclose, and claiming a cap there would be its own small
      # lie.
      def cap_sentence
        return "" unless @report.card_rows.size > @report.prize_rows.size

        "These are the #{@report.prize_rows.size} most at risk of this deck's " \
          "#{@report.card_rows.size} groups, a tie at the cut broken by name; the table below " \
          "carries every group's prize columns. "
      end
    end
  end
end
