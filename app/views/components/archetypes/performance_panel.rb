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
  # event with no tier lands.
  #
  # Splitting the *sample* by venue shipped as #160, and it needed no line here: this panel reads
  # `@scope.standings`, so the population itself narrows and every figure narrows with it. That is
  # the resolution the paragraph above was holding open — the population shrinks rather than the
  # panel growing a second number — and it is why the two sentences below are conditional now
  # instead of unconditional. The rule they keep is the page's rule everywhere else, that no
  # number quietly implies another.
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
    #
    # The closing sentence prints only when the counts really do mix the two. Unconditional inside
    # this branch it was false on 23 of the 48 archetypes carrying a list — the ones whose whole
    # sample is online, where it sat directly under "every event counted above" and contradicted
    # it — and it is the exact twin of the sentence Archetypes::SampleSelector prints over the
    # card report's population, which had the same defect and takes the same rule. Since the venue
    # axis, `?venue=online` reaches the same state deliberately.
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
                "every event counted above."
        else
                "#{@performance.online_events_count} of the #{@performance.events_count} " \
                  "#{'event'.pluralize(@performance.events_count)} counted above."
        end)
        plain " The counts above do not separate online play from paper." if @performance.blended?
      end

      leaderboard_note
    end

    # **The one thing the placement breakdown cannot say for itself.** The online rows come from
    # `play.limitlesstcg.com/decks/<slug>`, which publishes a leaderboard of *best finishes* and is
    # de-duplicated per player keeping the best result — so a placement there is selected on the
    # outcome, while the paper source is an event's whole results page. Measured on the production
    # data: of the placed standings, **online is 20.2 % firsts and 42.9 % top-4 (799 rows) against
    # paper's 0.9 % and 4.3 % (439 rows)**, and the rows are genuine wins rather than an import
    # bug. Left unsaid, "By placement: 1st 18 of 20" reads as a win rate on a page that refuses to
    # print one.
    #
    # It prints whenever the sample holds an online row at all, blended or not: a blend mixes a
    # leaderboard with a full history, which is the same distortion in smaller proportion, and the
    # sentence above already says what the proportion is.
    #
    # This is not a consequence of the venue axis — 23 of the 48 archetypes carrying a list open on
    # an all-online sample, so the column already read this way. What the venue axis changed is
    # that the sentence beside it had to stop claiming the counts blend, which left this state with
    # no qualification at all until this note.
    def leaderboard_note
      return unless @performance.online?

      p(class: "archetype-fact archetype-fact-muted") do
        "Online results are imported from a published leaderboard of best finishes, one row per " \
          "player and list, so the placements above are selected on the result rather than a " \
          "record of every online event."
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
