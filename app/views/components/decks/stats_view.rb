module Decks
  class StatsView < ApplicationComponent
    def initialize(deck:, results:)
      @deck = deck
      @results = results
    end

    def view_template
      div(class: "admin-container") do
        render Ui::PageHeader.new(title: "#{@deck.name} — Stats") do
          link_to "Back to Deck", helpers.deck_path(@deck), class: "btn btn-secondary"
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
        stat(counts["win"], "wins")
        stat(counts["loss"], "losses")
        stat(counts["draw"], "draws")
        stat(counts["timeout"], "timeouts")
        stat(total, "total")
        stat("#{win_rate}%", "win rate")
      end
    end

    def stat(value, label)
      div(class: "stat") do
        span(class: "stat-value") { value.to_s }
        span(class: "stat-label") { label }
      end
    end

    def archetype_table
      return if @results.empty?

      h2 { "By Archetype" }

      render Ui::AdminTable.new(columns: %w[Archetype W L D T Total Win%]) do
        @deck.archetype_breakdown(@results).each do |entry|
          archetype_row(entry[:name], entry[:counts], false)
          entry[:children].each do |child|
            archetype_row(child[:name], child[:counts], true)
          end
        end
      end
    end

    def archetype_row(name, counts, indent)
      total = counts.values.sum
      win_pct = total > 0 ? (counts["win"].to_f / total * 100).round(0) : 0

      tr do
        td { indent ? span(style: "padding-left: 1.5rem; color: #666;") { "\u2514 #{name}" } : plain(name) }
        td { counts["win"].to_s }
        td { counts["loss"].to_s }
        td { counts["draw"].to_s }
        td { counts["timeout"].to_s }
        td { strong { total.to_s } }
        td { "#{win_pct}%" }
      end
    end
  end
end
