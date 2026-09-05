module Archetypes
  # What the archetype has been recorded doing: counts, never rates, and never a share of a field.
  #
  # The heading says "recorded in Cartodex" and every sentence under it repeats the frame, because
  # the numbers are otherwise read as the field's. An imported sheet holds one archetype's rows,
  # so "9 standings at 4 events" is a statement about who has run an import, not about how often
  # the deck showed up. There is no win rate, for a reason Archetypes::Performance's own comment
  # now spells out: the online source publishes a W-L-T and the paper one does not, so the columns
  # are filled on part of any blended sample and empty on the rest — a rate over that describes the
  # online rows while being printed under a heading that covers both.
  #
  # This panel counts *every* standing in scope, including the ones nobody typed a decklist for,
  # while the card report below counts only the listed ones. That gap is named rather than left
  # looking like a discrepancy — it is the whole reason MetagameScope exposes both relations.
  #
  # It counts online events with paper ones, in every figure and every breakdown, and says so in
  # words rather than splitting the counters. `events_count` is COUNT(DISTINCT tournament_id) and
  # a weekly on play.limitlesstcg.com is as distinct an event as a Regional; splitting that one
  # figure would leave the standings count, the list count, the best placement and all three
  # breakdowns describing the blended population beside a counter that did not, and `by_tier`
  # cannot help — the online import forces `tier: "other"`, which is also where a genuine paper
  # event with no tier lands. Splitting the *sample* by venue is a selector and its own issue; the
  # rule this panel keeps in the meantime is the page's rule everywhere else, that no number
  # quietly implies another.
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

    # Ui::Stat prints the label it is handed and pluralises nothing — it is shared with the deck
    # and admin pages, where the labels are fixed strings — so the label arrives already agreeing
    # with its number. A one-standing archetype is the common case here, not a corner one: on the
    # production data one of the two recorded archetypes has exactly one standing, one event and
    # one list, and read "1 standings 1 events 1 lists".
    def counters
      div(class: "deck-show-stats") do
        counter(@performance.standings_count, "standing")
        counter(@performance.events_count, "event")
        counter(@performance.lists_count, "list")
        if @performance.best_placement
          render Ui::Stat.new(value: @performance.best_placement.ordinalize, label: "best placement")
        end
      end
    end

    def counter(value, noun)
      render Ui::Stat.new(value: value, label: noun.pluralize(value))
    end

    def facts
      div(class: "archetype-facts") do
        period
        online
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

    # How much of this sample is online play rather than paper, named because nothing else on the
    # page can show it: the pool axis puts an online weekly and a Regional in one bucket whenever
    # they share a Standard pool, and `by_tier` files every online event under "Other" beside the
    # paper events that have no tier. Printed only when there is a blend to name — a "0 online"
    # line on an archetype nobody has imported an online result for is noise that reads as a
    # warning about nothing.
    def online
      return unless @performance.online?

      count = @performance.online_standings_count

      p(class: "archetype-fact archetype-fact-muted") do
        plain(count == 1 ? "1 of these standings comes from an online tournament" :
                           "#{count} of these standings come from online tournaments")
        plain ", at "
        # "N of the N events" is a strange way to say "all of them", and on an archetype whose
        # every recorded event is online that is the sentence this would otherwise print.
        plain(if @performance.all_events_online?
                "every event counted above. "
        else
                "#{@performance.online_events_count} of the #{@performance.events_count} " \
                  "#{'event'.pluralize(@performance.events_count)} counted above. "
        end)
        plain "The counts above do not separate online play from paper."
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
          # "1 of these standings carries", not "carry": the subject is the count, not the
          # standings it is counting out of.
          plain "#{@performance.unlisted_count} of these standings "
          plain "#{@performance.unlisted_count == 1 ? 'carries' : 'carry'} no decklist, so the card "
          plain "report below speaks for the #{@performance.lists_count} "
          plain "#{'list'.pluralize(@performance.lists_count)} that #{@performance.lists_count == 1 ? 'does' : 'do'}."
        end
      end
    end

    def breakdowns
      div(class: "archetype-breakdowns") do
        placement_breakdown
        breakdown("By tier", "Tier", @performance.by_tier)
        breakdown("By division", "Division", @performance.by_division)
      end
    end

    # The one breakdown that can come back empty on well-formed data, and the one whose column
    # does not sum to the standings count printed above it. `placement` is nullable and there is
    # no band for "unknown", so the service simply has nowhere to put a standing nobody recorded a
    # placement for. On a page whose rule is that no number quietly implies another, that gap is
    # named here the way `unlisted_count` is named above.
    def placement_breakdown
      div(class: "archetype-breakdown") do
        h3 { "By placement" }

        if @performance.by_placement.any?
          breakdown_table("Placement", @performance.by_placement)
          unplaced_note
        else
          # Reachable, unlike the two below: every standing in scope carries a placement of nil.
          p(class: "empty-state") { "No placement recorded on these standings." }
        end
      end
    end

    def unplaced_note
      count = @performance.unplaced_count
      return unless count.positive?

      p(class: "archetype-fact archetype-fact-muted") do
        "#{count} of these standings #{count == 1 ? 'carries' : 'carry'} no placement, so " \
          "#{count == 1 ? 'it is' : 'they are'} not counted in this column."
      end
    end

    # No empty message, and no empty branch: `tier` and `division` are both NOT NULL columns
    # behind validated enums, and the service filter_maps over the enum's own key list
    # (Tournament.tiers.keys, TournamentStanding::DIVISIONS), so a scope holding any standing at
    # all yields at least one row here — and `breakdowns` is only called when it does. The two
    # empty messages that used to sit here ("No tier recorded.", "No age division recorded on
    # these standings.") were unreachable strings claiming an absence the schema forbids. The one
    # way past those enums is a write that bypasses validation, and the honest answer to that is a
    # section that is not drawn rather than a sentence stating something false about the data.
    def breakdown(title, column, rows)
      return if rows.empty?

      div(class: "archetype-breakdown") do
        h3 { title }
        breakdown_table(column, rows)
      end
    end

    def breakdown_table(column, rows)
      render Ui::DataTable.new(columns: [ column, "Standings" ]) do |table|
        rows.each do |label, count|
          table.row do
            table.cell { label }
            table.cell { count.to_s }
          end
        end
      end
    end
  end
end
