module Decks
  # One row per version of a deck, oldest first, with what was played under it. The stats page
  # opens with it because a deck's record only means something list by list: a win rate summed
  # over two lists describes neither.
  #
  # `results` is every result of the deck, whatever version the page is scoped to — the table is
  # also how the reader picks the scope, so it cannot shrink with it. Grouped here in Ruby: the
  # controller has already loaded them, and a GROUP BY would be a second read of the same rows.
  class VersionSummaryTable < ApplicationComponent
    COLUMNS = [ "Version", "Played", "Format", "W", "L", "D", "T", "Win%", "List" ].freeze

    def initialize(deck:, versions:, results:, selected_version: nil, periods: {})
      @deck = deck
      @periods = periods || {}
      @versions = versions
      @results_by_version = results.group_by(&:deck_version_id)
      @selected_version = selected_version
    end

    def view_template
      div(class: "version-summary") do
        render Ui::DataTable.new(columns: COLUMNS) do |t|
          @versions.each { |version| version_row(t, version) }
        end

        scope_line
      end
    end

    private

    def version_row(t, version)
      results = @results_by_version.fetch(version.id, [])
      counts = @deck.result_counts(results)

      t.row do
        t.cell { version_link(version) }
        t.cell { DeckVersions::Labels.played(@periods[version.id]) }
        t.cell { version.format_label }
        t.cell { counts["win"].to_s }
        t.cell { counts["loss"].to_s }
        t.cell { counts["draw"].to_s }
        t.cell { counts["timeout"].to_s }
        t.cell { win_rate(counts, results.size) }
        t.cell { link_to(version.number == 1 ? "View" : "Changes", deck_version_path(@deck, version)) }
      end
    end

    def version_link(version)
      if version == @selected_version
        strong { version.label }
      else
        link_to version.label, stats_deck_path(@deck, version: version.number)
      end
    end

    # Wins over every result, the formula the overall figure below uses, so the row of the only
    # version and the page's own win rate cannot disagree. A version nothing was played with gets
    # a dash: "0%" would read as a record, and there is none.
    def win_rate(counts, total)
      return "—" if total.zero?

      "#{(counts["win"].to_f / total * 100).round(0)}%"
    end

    def scope_line
      p(class: "version-summary-scope") do
        if @selected_version
          plain "Below: #{@selected_version.label} only. "
          link_to "Show all versions", stats_deck_path(@deck)
        else
          plain "Below: all versions."
        end
      end
    end
  end
end
