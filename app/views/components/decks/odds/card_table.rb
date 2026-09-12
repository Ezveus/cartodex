module Decks
  module Odds
    # One row per printing group — 2 Iono (PAL) plus 2 Iono (PAF) is one four-of, which is what both
    # the rules and the probabilities say. The "Seen" column reacts to all three steppers; the prize
    # column to the prizes taken stepper alone.
    class CardTable < ApplicationComponent
      include Formatting

      COLUMNS = [ "Card", "Copies", "In opening hand", "At least one prized",
                  "All copies unreachable", "Seen" ].freeze

      COLUMNS_WITHOUT_PRIZES = [ "Card", "Copies", "In opening hand", "Seen" ].freeze

      def initialize(report:)
        @report = report
      end

      def view_template
        section(class: "odds-panel") do
          h2 { "By card" }
          render Ui::DataTable.new(columns: @report.prizes? ? COLUMNS : COLUMNS_WITHOUT_PRIZES) do |t|
            @report.card_rows.each { |row| card_row(t, row) }
          end
        end
      end

      private

      # The header above and this branch are two reads of the same question, and Ui::DataTable takes
      # each cell's data-label from its position in the column list — so a disagreement mislabels
      # every column of the table rather than dropping one, silently, and only below the breakpoint.
      def card_row(table, row)
        table.row do
          table.cell { row.name }
          table.cell { row.copies.to_s }
          table.cell { percent(row.opening) }

          if @report.prizes?
            table.cell { percent(row.at_least_one_prized) }
            table.cell { render Cell.new(curve: row.all_prized_curve, index: 0, axis: :prizes) }
          end

          table.cell { render Cell.new(curve: row.accessible_curve, index: @report.default_seen) }
        end
      end
    end
  end
end
