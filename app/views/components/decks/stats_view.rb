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
      wins = count_by("win")
      total = @results.size
      win_rate = total > 0 ? (wins.to_f / total * 100).round(0) : 0

      div(class: "deck-show-stats") do
        stat(wins, "wins")
        stat(count_by("loss"), "losses")
        stat(count_by("draw"), "draws")
        stat(count_by("timeout"), "timeouts")
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

      grouped = build_archetype_tree

      render Ui::AdminTable.new(columns: %w[Archetype W L D T Total Win%]) do
        grouped.each do |entry|
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

    def build_archetype_tree
      by_archetype = @results.group_by(&:archetype)
      entries = {}

      by_archetype.each do |archetype, results|
        counts = result_counts(results)

        if archetype.nil?
          entries["unknown"] ||= { name: "Unknown", counts: empty_counts, children: [] }
          merge_counts!(entries["unknown"][:counts], counts)
          next
        end

        parent = archetype.parent || archetype
        parent_key = parent.id

        entries[parent_key] ||= { name: parent.name, counts: empty_counts, children: [] }
        merge_counts!(entries[parent_key][:counts], counts)

        if archetype.parent
          entries[parent_key][:children] << { name: archetype.name, counts: counts }
        end
      end

      entries.values.sort_by { |e| -e[:counts].values.sum }
    end

    def result_counts(results)
      counts = empty_counts
      results.each { |r| counts[r.result] += 1 }
      counts
    end

    def empty_counts
      { "win" => 0, "loss" => 0, "draw" => 0, "timeout" => 0 }
    end

    def merge_counts!(target, source)
      source.each { |k, v| target[k] += v }
    end

    def count_by(result)
      @results.count { |r| r.result == result }
    end
  end
end
