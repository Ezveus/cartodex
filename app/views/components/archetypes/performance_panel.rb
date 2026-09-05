module Archetypes
  # What the archetype has been recorded doing: counts, never rates, and never a share of a field.
  #
  # The heading says "recorded in Cartodex" and every sentence under it repeats the frame, because
  # the numbers are otherwise read as the field's. An imported sheet holds one archetype's rows,
  # so "9 standings at 4 events" is a statement about who has run an import, not about how often
  # the deck showed up. There is no win rate for a measured reason: the importer writes no
  # wins/losses/ties, and 1 of 94 production standings carries any.
  #
  # This panel counts *every* standing in scope, including the ones nobody typed a decklist for,
  # while the card report below counts only the listed ones. That gap is named rather than left
  # looking like a discrepancy — it is the whole reason MetagameScope exposes both relations.
  class PerformancePanel < ApplicationComponent
    def initialize(performance:)
      @performance = performance
    end

    def view_template
      section(class: "archetype-panel") do
        h2 { "Recorded in Cartodex" }

        if @performance.any?
          counters
          facts
          breakdowns
        else
          p(class: "empty-state") { "No standings recorded for this archetype in this sample." }
        end
      end
    end

    private

    def counters
      div(class: "deck-show-stats") do
        render Ui::Stat.new(value: @performance.standings_count, label: "standings")
        render Ui::Stat.new(value: @performance.events_count, label: "events")
        render Ui::Stat.new(value: @performance.lists_count, label: "lists")
        if @performance.best_placement
          render Ui::Stat.new(value: @performance.best_placement.ordinalize, label: "best placement")
        end
      end
    end

    def facts
      div(class: "archetype-facts") do
        period
        unlisted
      end
    end

    def period
      return unless @performance.first_date

      p(class: "archetype-fact") do
        if @performance.first_date == @performance.last_date
          plain "One event date on record: "
          strong { localize(@performance.first_date, format: :long) }
          plain "."
        else
          plain "Events from "
          strong { localize(@performance.first_date, format: :long) }
          plain " to "
          strong { localize(@performance.last_date, format: :long) }
          plain "."
        end
      end
    end

    # The card report speaks for a strictly smaller population whenever a sheet holds a row nobody
    # typed a list for, which is the common case. Saying so here is what stops the two list counts
    # on this page reading as a bug.
    def unlisted
      return unless @performance.unlisted_count.positive?

      p(class: "archetype-fact archetype-fact-muted") do
        if @performance.lists_count.zero?
          plain "None of these standings carries a decklist, so there is no card report below."
        else
          plain "#{@performance.unlisted_count} of these standings carry no decklist, so the card "
          plain "report below speaks for the #{@performance.lists_count} "
          plain "#{'list'.pluralize(@performance.lists_count)} that do."
        end
      end
    end

    def breakdowns
      div(class: "archetype-breakdowns") do
        breakdown("By placement", "Placement", @performance.by_placement,
                  "No placement recorded on these standings.")
        breakdown("By tier", "Tier", @performance.by_tier, "No tier recorded.")
        breakdown("By division", "Division", @performance.by_division,
                  "No age division recorded on these standings.")
      end
    end

    # Bands and tiers nobody reached are dropped by the service rather than printed as a row of
    # zeroes, so a breakdown really can come back empty — an event whose sheet records no
    # placement at all, or standings with no division. Each one therefore carries its own line
    # instead of collapsing to a heading over nothing.
    def breakdown(title, column, rows, empty_message)
      div(class: "archetype-breakdown") do
        h3 { title }

        if rows.any?
          render Ui::DataTable.new(columns: [ column, "Standings" ]) do |table|
            rows.each do |label, count|
              table.row do
                table.cell { label }
                table.cell { count.to_s }
              end
            end
          end
        else
          p(class: "empty-state") { empty_message }
        end
      end
    end
  end
end
