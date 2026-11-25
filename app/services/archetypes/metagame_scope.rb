module Archetypes
  # Answers one question for the metagame page — "which standings count?" — and is the only place
  # that answers it. The page asks it twice over, for two different populations: the performance
  # panel counts every recorded placement, while the card report can only speak for the ones whose
  # decklist somebody typed or imported. Letting one number stand for the other would overstate the
  # report's sample every time a sheet holds a row with no list, which is the common case.
  #
  # Scoping is not a refinement here, it is the difference between a true report and a false one.
  # Measured on the production data for Raging Bolt ex / Teal Mask Ogerpon ex: its 93 recorded
  # lists span three rotations and present 72 distinct cards blended, against 46-48 within any one
  # pool. A blended percentage describes no list anyone ever played.
  class MetagameScope < ApplicationService
    # Below this many lists a percentage is arithmetic on a handful of rows — three lists give
    # 33/67/100 and nothing else. The page says so rather than printing them unqualified, because
    # the default view of a freshly imported archetype is very often exactly that (the measured
    # one defaults to a pool holding three lists).
    SMALL_SAMPLE = 10

    # The selector's "no filter" value. A String because it travels through a query parameter and
    # is compared against one.
    ALL = "all".freeze

    Option = Struct.new(:value, :label, :lists_count, keyword_init: true)

    # The venue axis's values. Strings, because they travel through a query parameter and are
    # compared against one; `Result#venue` is the Symbol side, so nothing can compare the resolved
    # venue against the raw parameter by accident.
    VENUES = %w[all paper online].freeze

    # The one tournament a reader narrowed the report to: what the select and the note print, and
    # nothing a caller could mistake for the model — the report never needs more of it than this.
    SelectedTournament = Struct.new(:id, :name, :date, keyword_init: true)

    Result = Struct.new(
      :archetype, :standings, :listed_standings, :pool, :options,
      :lists_count, :online_lists_count, :unpooled, :unpooled_in_sample,
      :all_formats_lists_count, :venue, :venue_options, :venue_selectable,
      :tournament, :tournament_options, :tournament_selectable,
      keyword_init: true
    ) do
      # Whether any standing sits on an event with no Standard pool — a GLC or Expanded one. Those
      # are the lists the "All formats" option holds and no pool option can.
      #
      # Two members and not one, because two readers ask two different questions of the same word.
      # `unpooled?` is over **every** venue and feeds `selectable?`, so it must not move when a
      # venue is chosen — scoped, the *pool* control would vanish as a side effect of picking a
      # venue. `unpooled_in_sample?` is the venue-scoped one, and only the note reads it: measured
      # on the production data, Slowking has one GLC list, all paper, so under Online the sentence
      # "their lists are counted under All formats only" sent the reader after a list the current
      # sample excludes entirely — 21 such states over 7 archetypes.
      def unpooled? = unpooled
      def unpooled_in_sample? = unpooled_in_sample
      def all_formats? = pool.nil?

      # Whether this sample holds any online list at all, which is what decides whether the note
      # under the selector has anything to say. It is not "whether the sample blends": under
      # `venue: :online` every list is online, and the sentence claiming the report counts both
      # kinds together has to withhold itself. That is `online_lists_count < lists_count`, which
      # the component asks separately — and which was already the right question before this axis
      # existed, since 23 of the 48 archetypes carrying a list open on an all-online sample and
      # were told their report counted paper lists that do not exist.
      def online_lists? = online_lists_count.positive?

      # Whether the sample really holds both kinds, which is the question the note above the card
      # report asks — and it lives here rather than in the component because every predicate
      # beside it does, and because Archetypes::Performance::Result carries the same rule over its
      # own population. Two components computing it is how the two halves of one page come to
      # disagree.
      def blended? = online_lists_count.positive? && online_lists_count < lists_count
      def small_sample? = lists_count.positive? && lists_count < SMALL_SAMPLE
      def no_lists? = lists_count.zero?

      # Whether there is a genuine choice, which is not the same as having more than one option:
      # an archetype with standings in exactly one pool and nowhere else gets a select of
      # "TEF-PBL — 1 list" and "All formats — 1 list", two labels for one sample. Measured on the
      # production data, that is not a corner case — most archetypes with any standings at all are
      # in it. One pool *plus* an event outside Standard is the opposite shape: two labels naming
      # two genuinely different samples.
      #
      # `unpooled?` cannot answer on its own, which is why it is conjoined rather than or'd in: an
      # archetype whose every standing sits outside Standard is unpooled and has "All formats" as
      # its *only* option, however many events that spans. Promising a choice there renders a
      # <select> of one, which is the thing Archetypes::SampleSelector drops the control to avoid.
      def selectable?
        pool_options = options.count { |option| option.value != ALL }
        pool_options > 1 || (pool_options == 1 && unpooled?)
      end

      # Whether switching could actually show more, which is what the notice under the selector
      # promises. False when the current sample is already the largest.
      #
      # It reads `options` alone, and adding `venue_options` to it would be dead code: `options`
      # always carries an entry equal to the selected pool's own total, and `venue_options`' "All"
      # *is* that same total, so the two spellings cannot disagree. Measured over the 147
      # reachable (archetype, pool, venue) states in production, they diverge on 0 — under
      # `pool=TEF-PBL&venue=paper` on Dragapult ex the promise is already true through the pool
      # select, which reads "TEF-PBL — 118 lists" beside a 98-list sample.
      def fuller_sample_available? = options.any? { |option| option.lists_count > lists_count }

      # Whether the venue control is a genuine choice: the selection holds standings under **both**
      # venues, and deliberately not `venue_options.size > 1` — those always number three, so that
      # spelling is always true. "All — 20 lists" beside "Online — 20 lists" is two labels for one
      # sample, the same non-choice `selectable?` drops the pool control to avoid. Measured, the
      # majority shape: of the 59 (archetype, pool) buckets in production, 12 are paper-only and 23
      # online-only, so the control is absent from 35 of them.
      #
      # "Both venues" and not "more than one non-empty cell", which is what it first counted: the
      # two agree for a single pool and diverge under "All formats", where the cells span pools —
      # see `venue_present?`.
      def venue_selectable? = venue_selectable

      # Whether the tournament control is a genuine choice: the pool + venue selection holds at
      # least two events. One event is the same sample as "All tournaments" — two labels for one
      # sample, the shape both controls above already refuse — and a URL naming it is clamped too,
      # so the page never pins a filter it offers no control to remove.
      def tournament_selectable? = tournament_selectable
    end

    # `pool_param` is whatever arrived in the query string: a pool id, ALL, nil, or junk —
    # `params[:pool]` can be an Array or a Hash, neither of which responds to `to_i`, and this
    # action is reachable by anyone with a session. `to_s` first, then fall back to the default.
    #
    # `venue_param` gets the same `to_s` for symmetry, and it buys something different: this axis
    # resolves by `VENUES.include?`, which answers false for nil, an Array or a Hash without
    # raising, so the guard fails closed with or without it. What `to_s` actually does here is
    # widen the input to accept a Symbol, which is what an internal caller would pass.
    #
    # `tournament_param` likewise: an id, ALL, nil or junk, `to_s` first. It resolves against the
    # events this archetype holds standings at, never against the `tournaments` table, so an id
    # naming somebody else's event is junk like any other.
    def initialize(archetype:, pool_param: nil, venue_param: nil, tournament_param: nil)
      @archetype = archetype
      @pool_param = pool_param.to_s
      @venue_param = venue_param.to_s
      @tournament_param = tournament_param.to_s
    end

    # Pool, then venue, then tournament: each axis resolves inside the ones before it, which is
    # what "cascading" means here. The tournament never drives the pool or the venue.
    def call
      pool = selected_pool
      venue = selected_venue(pool)
      tournament = selected_tournament(pool, venue)
      totals = fold(selection_rows(pool, venue, tournament))

      Result.new(
        archetype: @archetype,
        standings: standings_scope(pool, venue, tournament),
        listed_standings: standings_scope(pool, venue, tournament).where.not(deck_id: nil),
        pool: pool,
        options: options,
        lists_count: totals.lists,
        online_lists_count: venue == :paper ? 0 : fold(selection_rows(pool, :online, tournament)).lists,
        unpooled: buckets.any? { |bucket| bucket.pool_id.nil? },
        unpooled_in_sample: selection_rows(nil, venue, tournament).any? { |bucket| bucket.pool_id.nil? },
        # Every pool, *this* venue — and *this* tournament, since a pool change carries it along
        # and keeps it: "All formats" holds every event. The card report's empty state is the only
        # reader, and it needs a count the reader's click would actually deliver: `options`' "All
        # formats" is venue-independent, so on a pool with placements and no typed list it
        # promised lists that the current venue may not hold, and the one form carries the venue
        # along with the click. A fold over buckets already in memory, so no query.
        all_formats_lists_count: fold(selection_rows(nil, venue, tournament)).lists,
        venue: venue,
        venue_options: venue_options(pool),
        venue_selectable: venue_selectable?(pool),
        tournament: tournament && SelectedTournament.new(id: tournament.tournament_id,
                                                         name: tournament.tournament_name,
                                                         date: tournament.last_on),
        tournament_options: tournament_options(pool, venue),
        tournament_selectable: tournament_selectable?(pool, venue)
      )
    end

    private

    # A bucket is one tournament, which sits in exactly one (pool, venue) cell. `online` and
    # `tournament_id` are nil on a folded bucket, which is the only thing that distinguishes an
    # event from a total built out of events.
    Bucket = Struct.new(:pool_id, :online, :tournament_id, :tournament_name, :standings, :lists,
                        :last_on, keyword_init: true)

    # One grouped query, and every number the selector prints comes out of it: per Standard pool
    # (NULL for the non-Standard events, which carry no pool by design) and per venue, how many
    # standings this archetype has, how many of them carry a list, and when its most recent event
    # there was.
    #
    # COUNT(DISTINCT deck_id) rather than COUNT(*): NULLs are ignored by DISTINCT, so this is the
    # list count and the standings count in the same pass, without a second query or a filtered
    # relation.
    #
    # It is grouped by **tournament**, and the pool and the venue ride along as columns each event
    # carries exactly one of. That is what lets the tournament axis cost no query: every pool and
    # venue figure was already a fold of rows, and now it folds events instead of cells. Measured
    # on a production copy, at most 66 events for one archetype (6.4 per cell on average), and the
    # plan is unchanged — `index_tournament_standings_on_archetype_id`, then the tournament's
    # primary key — so the page stays at its 17 queries. The price is `fold`'s, written there.
    #
    # `tournaments.name` is a bare column beside a GROUP BY on `tournaments.id`, which SQLite takes
    # from the group's one row: every column of a tournament is functionally dependent on its id.
    #
    # `online` needs no cast and must not be given one. SQLite reports a decltype for a bare
    # column reference, so the adapter's `cast_values` hands back true/false here — measured,
    # `select_all(…).column_types["online"]` is ActiveModel::Type::Boolean where
    # `column_types["MAX(tournaments.date)"]` is the bare Value that `to_date` below exists for.
    # Wrapping the column in an expression (a COALESCE, a CASE) is what would lose that and hand
    # back a 0 that is truthy in Ruby.
    def buckets
      @buckets ||= TournamentStanding
        .where(archetype_id: @archetype.id)
        .joins(:tournament)
        .group("tournaments.id")
        .pluck(
          Arel.sql("tournaments.standard_pool_id"),
          Arel.sql("tournaments.online"),
          Arel.sql("tournaments.id"),
          Arel.sql("tournaments.name"),
          Arel.sql("COUNT(*)"),
          Arel.sql("COUNT(DISTINCT tournament_standings.deck_id)"),
          Arel.sql("MAX(tournaments.date)")
        )
        .map do |pool_id, online, tournament_id, name, standings, lists, last_on|
          Bucket.new(pool_id: pool_id, online: online, tournament_id: tournament_id,
                     tournament_name: name, standings: standings, lists: lists,
                     last_on: to_date(last_on))
        end
    end

    # The rows of one selection: a pool, or every pool when the reader has chosen "All formats".
    # `pool_id` is overloaded — nil means "every pool" as a *selection* and "the non-Standard
    # bucket" as *data* — and every venue figure below reads it as the selection. Read the other
    # way, the venue control would vanish for the 40 archetypes with no non-Standard event and
    # would count only the GLC lists for the other 8, so a reader choosing "All formats" would
    # lose the control with no way back but editing the URL. Measured, 24 of the 48 archetypes
    # carrying a list have a blended All-formats sample, so that is the majority state.
    #
    # `tournament`, when given, is one of these buckets and narrows the rows to itself.
    def selection_rows(pool, venue, tournament = nil)
      rows = pool ? buckets.select { |bucket| bucket.pool_id == pool.id } : buckets
      rows = rows.select { |bucket| bucket.online == (venue == :online) } unless venue == :all
      return rows if tournament.nil?

      rows.select { |bucket| bucket.tournament_id == tournament.tournament_id }
    end

    # "Does this half of the selection hold anything?" — one definition, called by the clamp and by
    # `venue_selectable?`, because the two ask the same question and answered it in two spellings.
    #
    # That divergence was a live defect: `venue_selectable?` counted the selection's *non-empty
    # cells* rather than its *venues*, which is the same thing for one pool (a pool has at most a
    # paper row and an online row) and not for "All formats", where the cells span pools. Measured
    # on the production data, one archetype — Mega Greninja ex / Dragapult ex, one paper standing
    # in TEF-PBL and one at a non-Standard event — was offered a Venue select reading
    # "All — 2 lists / Paper — 2 lists / Online — 0 lists": two labels for one sample *and* a dead
    # option that silently clamps back to All when clicked, which is both of the shapes this
    # control exists to avoid.
    def venue_present?(pool, venue)
      selection_rows(pool, venue).sum(&:standings).positive?
    end

    # Sums a set of events into one bucket. Sound because a deck cannot be counted twice — measured
    # on the production data, 0 decks carry standings under both venues and 0 carry more than one
    # standing at all, so the fold matches the single grouped count on 59 buckets of 59 and
    # 1223 == 1223 across pools. Re-measured when the buckets became events (2026-11-25): still 0
    # decks with more than one standing, and 0 at two events under one archetype.
    #
    # Where that stops being true it over-counts, and that is a pre-existing property extended
    # along a second axis rather than a new one: `total` has always been `buckets.sum(&:lists)`,
    # which double-counts a deck holding standings in two pools. Nothing in the schema forbids the
    # shape — `index_tournament_standings_on_deck_id` is not unique, and two standings pointing at
    # one deck is legitimate — so a test names the behaviour rather than asserting an identity the
    # fold cannot violate. Making it exact costs a second query per option; a tournament's own
    # count is exact either way, since each is a single event. Since the buckets became events the
    # over-count reaches *inside* a cell too — a deck at two events of one pool — which is the same
    # property on a third axis, named by its own test; a second grouped query for the tournament
    # options would have kept cells exact, at one more query on a page three assertions pin at 17.
    def fold(rows)
      Bucket.new(
        pool_id: rows.first&.pool_id, online: nil, tournament_id: nil, tournament_name: nil,
        standings: rows.sum(&:standings), lists: rows.sum(&:lists),
        last_on: rows.filter_map(&:last_on).max
      )
    end

    # SQLite hands MAX(date) back as a String through an Arel.sql pluck, since there is no column
    # type for Rails to infer from an aggregate. Nothing else in the class may care which it got.
    def to_date(value)
      value.is_a?(String) ? Date.parse(value) : value
    end

    # `named` preloads both bounds, which StandardPool#name reads — without it every option in the
    # selector costs two extra queries.
    def pools
      @pools ||= StandardPool.named.where(id: buckets.filter_map(&:pool_id)).index_by(&:id)
    end

    # One folded bucket per pool, most recent first — the order a player thinks in, with the pool
    # id breaking a tie so two pools sharing a last event date cannot swap places between two
    # loads of the same page.
    #
    # The fold is what makes the pool options venue-independent *by construction* rather than by
    # remembering to: unfolded, a blended pool yields two buckets and the selector would offer
    # "TEF-PBL — 98 lists" beside "TEF-PBL — 20 lists" in one <select>.
    def pool_buckets
      @pool_buckets ||= buckets.reject { |bucket| bucket.pool_id.nil? }
                               .group_by(&:pool_id).values.map { |rows| fold(rows) }
                               .sort_by { |bucket| [ bucket.last_on, bucket.pool_id ] }
                               .reverse
    end

    # Every option carries its list count. Choosing between rotations without them is blind, and
    # the fullest sample is not always the most recent one — for the measured archetype the newest
    # pool holds 3 lists and the oldest 68.
    #
    # These labels do **not** move when a venue is chosen: "SVI-BLK — 56 lists" reads 56 whether
    # or not Online is selected. Recounting each pool within the current venue is the alternative,
    # and it is more literally true of a click and worse in practice — labels would shift under
    # the reader between loads, and options would appear reading "SVI-BLK — 0 lists". Stable
    # labels are honest here *because of* the clamp in `selected_venue`, and only because of it:
    # clicking "SVI-BLK — 56 lists" under Online resets the venue and shows 56 lists.
    def options
      pool_options = pool_buckets.filter_map do |bucket|
        pool = pools[bucket.pool_id] or next
        Option.new(value: pool.id.to_s, label: "#{pool.name} — #{list_label(bucket.lists)}",
                   lists_count: bucket.lists)
      end

      pool_options + [ Option.new(value: ALL, label: "All formats — #{list_label(total.lists)}",
                                  lists_count: total.lists) ]
    end

    def list_label(count)
      "#{count} #{'list'.pluralize(count)}"
    end

    # The most recent pool present, not the best-populated one. Defaulting to the fullest sample
    # would answer "what does this deck play?" with data from a rotation the heading never names;
    # telling the truth about the current one, with the fuller samples one labelled click away, is
    # the honest trade. Nil when the archetype has no Standard event at all.
    def default_pool
      @default_pool ||= pool_buckets.filter_map { |bucket| pools[bucket.pool_id] }.first
    end

    def selected_pool
      return nil if @pool_param == ALL

      # A blank or malformed parameter casts to 0, which no pool id can be, so an unknown value
      # lands on the default rather than on a 404 or an empty page.
      pools[@pool_param.to_i] || default_pool
    end

    # `paper`/`online` only when the selection actually holds a standing under it, otherwise the
    # whole venue axis falls back to `:all` — the clamp, and it is recorded in the Result rather
    # than merely applied to the relation, because the select above the report and the report
    # itself must not disagree about which sample is showing.
    #
    # The empty cell is neither rare nor random: every pool other than TEF-PBL holds zero online
    # lists, so 10 of the 38 cells belonging to the 9 multi-pool archetypes with a blended pool
    # are empty, and `?pool=<SVI-BLK>&venue=online` is exactly what clicking a pool label while
    # Online is selected produces. An unknown value falls back the same way `?pool=` already does,
    # rather than on a 404 or an empty page.
    #
    # "Holds a standing" and not "holds a list", following the pool axis: `options` already renders
    # "TEF-PBL — 0 lists" for a pool with recorded placements and no typed decklist, and it must,
    # because Archetypes::Performance counts placements the card report cannot see.
    def selected_venue(pool)
      return :all unless VENUES.include?(@venue_param)

      venue = @venue_param.to_sym
      return :all if venue != :all && !venue_present?(pool, venue)

      venue
    end

    # Counted within the current selection, which is the symmetry the pool axis's stability buys:
    # pool labels do not move with the venue, so venue labels move with the pool.
    def venue_options(pool)
      VENUES.map do |value|
        lists = fold(selection_rows(pool, value.to_sym)).lists
        # `capitalize` rather than a parallel label table: the three labels are exactly the
        # values, and Archetypes::Performance#by_division already reads its own enum this way.
        Option.new(value: value, label: "#{value.capitalize} — #{list_label(lists)}",
                   lists_count: lists)
      end
    end

    # A half is an option from one standing, with no threshold of its own. A threshold at
    # SMALL_SAMPLE was weighed and refused on measurement: it would remove the control from 17 of
    # the 48 archetypes, *including* Lillie's Clefairy ex — paper half of 9 lists, and one of the
    # four archetypes whose two halves genuinely disagree — so the threshold would silence a
    # motivating case. `small_sample?` already says what a nine-list sample is worth, and it now
    # fires on a venue half as readily as on a pool.
    def venue_selectable?(pool)
      venue_present?(pool, :paper) && venue_present?(pool, :online)
    end

    # The tournament is a plain `tournament_id` predicate on the standings themselves, so it needs
    # no join of its own; it is applied before the early return so "All formats, every venue, one
    # event" — the shape a GLC event is reached in — is still narrowed.
    def standings_scope(pool, venue, tournament)
      scope = TournamentStanding.where(archetype_id: @archetype.id)
      scope = scope.where(tournament_id: tournament.tournament_id) if tournament
      # Today's exact relation for today's exact case, so the unfiltered page cannot regress on a
      # join it never needed.
      return scope if pool.nil? && venue == :all

      scope = scope.joins(:tournament)
      scope = scope.where(tournaments: { standard_pool_id: pool.id }) if pool
      scope = scope.where(tournaments: { online: venue == :online }) unless venue == :all
      scope
    end

    # The selection's events, most recent first, the id breaking a tie so two events on one date
    # cannot swap places between two loads of the same page — the order `pool_buckets` keeps.
    def tournament_buckets(pool, venue)
      selection_rows(pool, venue).sort_by { |bucket| [ bucket.last_on, bucket.tournament_id ] }
                                 .reverse
    end

    # Resolved inside the pool + venue selection: an id outside it — a stale link, a venue change
    # that left the event behind, an event this archetype was never recorded at, junk — clamps to
    # "All tournaments", and so does the selection's only event (see
    # `Result#tournament_selectable?`). The clamp is recorded in the Result for the reason the
    # venue's is: the select above the report and the report itself must not disagree.
    def selected_tournament(pool, venue)
      return nil if @tournament_param.empty? || @tournament_param == ALL
      return nil unless tournament_selectable?(pool, venue)

      # Compared as Strings rather than through `to_i`, which would read "12junk" as 12.
      selection_rows(pool, venue).find { |bucket| bucket.tournament_id.to_s == @tournament_param }
    end

    # Counted within the selection: these labels move with the pool and the venue, as the venue's
    # move with the pool. The date is in the label because the name alone is not an identity —
    # measured, 55 tournaments share their name with another — and it is the spelling
    # TournamentEntry#picker_label prints. "All tournaments" leads, as the default does in Venue.
    def tournament_options(pool, venue)
      all = Option.new(value: ALL,
                       label: "All tournaments — #{list_label(fold(selection_rows(pool, venue)).lists)}",
                       lists_count: fold(selection_rows(pool, venue)).lists)

      [ all ] + tournament_buckets(pool, venue).map do |bucket|
        Option.new(value: bucket.tournament_id.to_s,
                   label: "#{bucket.tournament_name} (#{I18n.l(bucket.last_on)}) — " \
                          "#{list_label(bucket.lists)}",
                   lists_count: bucket.lists)
      end
    end

    def tournament_selectable?(pool, venue)
      selection_rows(pool, venue).size > 1
    end

    def total = @total ||= fold(buckets)
  end
end
