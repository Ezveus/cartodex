module Decks
  # Renders an archetype win/loss breakdown (as produced by Deck#archetype_breakdown)
  # as a table, with parent archetypes and their indented children. Shared by the
  # per-deck stats page and the aggregated matchups page.
  class ArchetypeBreakdownTable < ApplicationComponent
    def initialize(breakdown:)
      @breakdown = breakdown
    end

    def view_template
      render Ui::DataTable.new(columns: %w[Archetype W L D T Total Win%]) do |t|
        @breakdown.each do |entry|
          archetype_row(t, entry[:name], entry[:counts], false)
          entry[:children].each do |child|
            archetype_row(t, child[:name], child[:counts], true)
          end
        end
      end
    end

    private

    def archetype_row(t, name, counts, indent)
      total = counts.values.sum
      win_pct = total > 0 ? (counts["win"].to_f / total * 100).round(0) : 0

      t.row do
        t.cell { indent ? span(style: "padding-left: 1.5rem; color: #666;") { "└ #{name}" } : plain(name) }
        t.cell { counts["win"].to_s }
        t.cell { counts["loss"].to_s }
        t.cell { counts["draw"].to_s }
        t.cell { counts["timeout"].to_s }
        t.cell { strong { total.to_s } }
        t.cell { "#{win_pct}%" }
      end
    end
  end
end
