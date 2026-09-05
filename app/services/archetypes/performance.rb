module Archetypes
  # What an archetype has been recorded doing: counts and placements, never rates.
  #
  # Everything here is worded "recorded in Cartodex" on the page it feeds, and that is not
  # modesty. A sheet imported from one archetype's Limitless page holds only that archetype's
  # rows, so the database never sees the rest of the field and cannot produce a share of it.
  #
  # There is no win rate either, and the reason changed shape when the online source landed rather
  # than going away. It used to be that nothing wrote the columns at all: the paper source
  # (limitlesstcg.com/decks/<id>/results) publishes no record, so Tournaments::StandingsImporter
  # wrote player, division, placement, archetype and creator and never wins/losses/ties, and
  # exactly 1 of 94 production standings carried a W-L-T — the one somebody typed by hand.
  # play.limitlesstcg.com does publish a W - L - T on every row, so the importer now writes all
  # three for an online standing. That makes the columns populated on part of a sample and empty
  # on the rest, which is worse for a rate than empty everywhere: a win rate computed here would
  # describe the online rows alone while being printed under a heading that covers both, and one
  # computed over the whole sample would divide the online wins by everybody's games. The figure
  # belongs to a page that can say which rows it speaks for, and that page is its own issue. What
  # ships instead is the count below — how much of this sample is online — so the blend is named
  # rather than left to be discovered.
  class Performance < ApplicationService
    # Fixed bands, deliberately not Tournament::TOP_CUT_BANDS. That constant maps an *attendance*
    # to a top-cut size (it is what TournamentEntry#top_cut_size reads), so telling whether a
    # placement made the cut needs the event's field size — and the importer never writes one: all
    # three *_participant_count columns are nil on every imported event, measured. A cut-aware
    # band would be nil for every row an import produces.
    PLACEMENT_BANDS = [
      [ "1st",   1..1 ],
      [ "2-4",   2..4 ],
      [ "5-8",   5..8 ],
      [ "9-16",  9..16 ],
      [ "17-32", 17..32 ],
      [ "33-64", 33..64 ],
      [ "65+",   65..Float::INFINITY ]
    ].freeze

    Result = Struct.new(
      :standings_count, :events_count, :lists_count, :placed_count,
      :online_standings_count, :online_events_count,
      :first_date, :last_date, :best_placement,
      :by_placement, :by_tier, :by_division,
      keyword_init: true
    ) do
      def any? = standings_count.positive?
      # Whether this sample blends online play with paper at all. Nothing here says so when it
      # does not: a "0 online standings" line on an archetype nobody has imported an online
      # result for is noise that reads as a warning.
      def online? = online_standings_count.positive?
      # Whether every event in the sample is an online one, which is the case the page words
      # differently — "N of these M" is a strange way to say "all of them".
      def all_events_online? = events_count.positive? && online_events_count == events_count
      # Standings whose decklist nobody typed. Named on the page so the report's smaller sample
      # is explained rather than looking like a discrepancy.
      def unlisted_count = standings_count - lists_count
      # Standings recorded without a placement. `by_placement` cannot show them — there is no band
      # for "unknown" — so its column sums to less than standings_count, and on a page whose whole
      # point is that no number quietly implies another, that gap has to be named too.
      def unplaced_count = standings_count - placed_count
    end

    # The full standings relation, not the listed subset: a placement is a recorded result whether
    # or not anybody typed the decklist, and counting only the listed ones would understate an
    # archetype's record by however much of the sheet is still bare.
    def initialize(standings:)
      @standings = standings
    end

    def call
      count, events, lists, placed, online_count, online_events, best, first_on, last_on = totals

      Result.new(
        standings_count: count.to_i,
        events_count: events.to_i,
        lists_count: lists.to_i,
        placed_count: placed.to_i,
        online_standings_count: online_count.to_i,
        online_events_count: online_events.to_i,
        best_placement: best,
        first_date: to_date(first_on),
        last_date: to_date(last_on),
        by_placement: by_placement,
        by_tier: by_tier,
        by_division: by_division
      )
    end

    private

    # Nine numbers, one query. DISTINCT ignores NULLs, so the listed subset costs nothing extra.
    #
    # COUNT(**DISTINCT** deck_id) and not COUNT(deck_id): nothing stops two standings pointing at
    # one deck — `index_tournament_standings_on_deck_id` is not unique — and MetagameScope counts
    # the sample distinctly. Without the DISTINCT the panel would print one number while the
    # selector above it printed another, for the same sample.
    #
    # **The events figure stays whole, and the panel names the split beside it.** `events_count`
    # is COUNT(DISTINCT tournament_id) and now mixes a weekly online tournament with a Regional;
    # the tempting fix is to report two numbers instead of one and let "events" mean paper events.
    # That is the wrong trade here for three reasons that were weighed rather than assumed: the
    # figure is true as it stands (they are distinct events), every other number on the panel —
    # standings, lists, best placement, all three breakdowns — is over the same blended
    # population and would have to split with it or contradict it, and §6 of the online import's
    # design forces `tier: "other"` on every online event, so `by_tier` cannot tell them apart
    # either and a split events count would be the one figure that could. Splitting the *sample*
    # by venue is a selector, a page and its own issue. So both counts come back whole and the
    # two online figures ride beside them, for the panel to name the mixture in words.
    #
    # The two online terms cost no query: they are CASE expressions on a join this pick already
    # makes, and this page is pinned at a flat query count by a controller test.
    def totals
      @totals ||= @standings.joins(:tournament).pick(
        Arel.sql("COUNT(*)"),
        Arel.sql("COUNT(DISTINCT tournament_standings.tournament_id)"),
        Arel.sql("COUNT(DISTINCT tournament_standings.deck_id)"),
        Arel.sql("COUNT(tournament_standings.placement)"),
        Arel.sql("SUM(CASE WHEN tournaments.online THEN 1 ELSE 0 END)"),
        Arel.sql("COUNT(DISTINCT CASE WHEN tournaments.online THEN tournament_standings.tournament_id END)"),
        Arel.sql("MIN(tournament_standings.placement)"),
        Arel.sql("MIN(tournaments.date)"),
        Arel.sql("MAX(tournaments.date)")
      ) || []
    end

    # SQLite returns an aggregate over a date column as a String — there is no column type for
    # Rails to infer from MIN()/MAX().
    def to_date(value)
      value.is_a?(String) ? Date.parse(value) : value
    end

    # Ordered by the band table, and bands nobody reached are dropped rather than printed as zero:
    # a column of zeroes down to "65+" says less than its absence does.
    def by_placement
      placements = @standings.where.not(placement: nil).pluck(:placement)

      PLACEMENT_BANDS.filter_map do |label, range|
        count = placements.count { |placement| range.cover?(placement) }
        [ label, count ] unless count.zero?
      end
    end

    def by_tier
      counts = @standings.joins(:tournament).group("tournaments.tier").count

      Tournament.tiers.keys.filter_map do |tier|
        count = counts[tier]
        [ Tournament::TIER_LABELS.fetch(tier, tier), count ] if count&.positive?
      end
    end

    # junior / senior / masters, the order players read — TournamentStanding::DIVISIONS is that
    # order, while `group(:division)` on its own comes back alphabetical (junior, masters, senior).
    # The standings sheet had to make the same correction in SQL for its page boundaries.
    def by_division
      counts = @standings.group(:division).count

      TournamentStanding::DIVISIONS.filter_map do |division|
        count = counts[division]
        [ division.capitalize, count ] if count&.positive?
      end
    end
  end
end
