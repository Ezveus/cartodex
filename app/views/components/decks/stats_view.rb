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

        deck_archetype_line
        overall_stats
        archetype_table
      end
    end

    private

    def deck_archetype_line
      return unless @deck.archetype

      p(class: "deck-stats-archetype") do
        plain "Archetype: "
        strong { @deck.archetype.name }
      end
    end

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
      render Decks::ArchetypeBreakdownTable.new(breakdown: @deck.archetype_breakdown(@results))
    end
  end
end
