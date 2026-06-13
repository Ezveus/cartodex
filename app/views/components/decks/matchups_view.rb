module Decks
  # Aggregated matchups across all of the user's decks, grouped by the player's
  # own deck archetype. Each section shows the cumulative win/loss record and a
  # breakdown by the opposing archetype.
  class MatchupsView < ApplicationComponent
    def initialize(matchup_groups:)
      @matchup_groups = matchup_groups
    end

    def view_template
      div(class: "admin-container") do
        render Ui::PageHeader.new(title: "Matchups by Archetype") do
          link_to "Back to Decks", decks_path, class: "btn btn-secondary"
        end

        if @matchup_groups.empty?
          empty_state
        else
          @matchup_groups.each { |group| archetype_section(group) }
        end
      end
    end

    private

    def empty_state
      p do
        plain "No decks have an archetype yet. Tag a deck with an archetype to see aggregated matchups here."
      end
    end

    def archetype_section(group)
      div(class: "matchup-archetype-section") do
        h2 { group[:archetype].name }
        deck_count_line(group[:deck_count])
        overall_stats(group[:counts])

        if group[:breakdown].any?
          render Decks::ArchetypeBreakdownTable.new(breakdown: group[:breakdown])
        else
          p(class: "matchup-no-results") { "No results logged yet." }
        end
      end
    end

    def deck_count_line(count)
      p(class: "matchup-deck-count") { "#{count} #{count == 1 ? 'deck' : 'decks'}" }
    end

    def overall_stats(counts)
      total = counts.values.sum
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
  end
end
