module Decks
  class StatsView < ApplicationComponent
    def initialize(deck:, results:)
      @deck = deck
      @results = results
    end

    def view_template
      div(class: "admin-container") do
        render Ui::PageHeader.new(title: "#{@deck.name} — Stats") do
          link_to "Back to Deck", deck_path(@deck), class: "btn btn-secondary"
        end

        overall_stats
        archetype_table
      end
    end

    private

    def overall_stats
      counts = @deck.result_counts(@results)
      total = @results.size
      win_rate = total > 0 ? (counts["win"].to_f / total * 100).round(0) : 0

      div(class: "deck-show-stats") do
        render Ui::Stat.new(value: counts["win"], label: "wins")
        render Ui::Stat.new(value: counts["loss"], label: "losses")
        render Ui::Stat.new(value: counts["draw"], label: "draws")
        render Ui::Stat.new(value: counts["timeout"], label: "timeouts")
        render Ui::Stat.new(value: total, label: "total")
        render Ui::Stat.new(value: "#{win_rate}%", label: "win rate")
      end
    end

    def archetype_table
      return if @results.empty?

      h2 { "By Archetype" }

      render Ui::DataTable.new(columns: %w[Archetype W L D T Total Win%]) do |t|
        @deck.archetype_breakdown(@results).each do |entry|
          archetype_row(t, entry[:name], entry[:counts], false)
          entry[:children].each do |child|
            archetype_row(t, child[:name], child[:counts], true)
          end
        end
      end
    end

    def archetype_row(t, name, counts, indent)
      total = counts.values.sum
      win_pct = total > 0 ? (counts["win"].to_f / total * 100).round(0) : 0

      t.row do
        t.cell { indent ? span(style: "padding-left: 1.5rem; color: #666;") { "\u2514 #{name}" } : plain(name) }
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
