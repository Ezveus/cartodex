module Cards
  # How the card is played across the recorded field: for each archetype with a list playing it,
  # the share of that archetype's lists that do, then the same per Standard pool and per tournament.
  #
  # **The figure is the analysis page's, computed the same way.** `/archetypes/:slug/analysis`
  # prints, for a card, `Archetypes::CardStats::Entry` over `MetagameScope#listed_standings`: the
  # sample's distinct deck ids, the decks holding a `deck_cards` row under the card's
  # `CardStats::GROUPING_KEY`, `(100.0 * playing / lists).round(1)`, and the per-deck SUM of
  # copies. This reproduces each of those by set arithmetic over deck ids, never by folding
  # per-event counts the way `MetagameScope`'s *selector labels* do — so a node stays exact where a
  # label over-counts (one deck at two events; measured 0 such decks on 2026-11-25), and every node
  # carries the analysis parameters it reproduces so a test can compare the two directly.
  #
  # **The sample is chosen the way the analysis chooses it**: Standard pool, then venue, then
  # tournament, each resolving inside the ones before it and clamping to "all" where it names
  # nothing the card is played in. The default pool is "All formats", the owner's choice
  # (2026-11-27), so the page opens on the whole tree; the analysis defaults to the newest pool
  # because it reports one archetype, while this reports a card across all of them.
  #
  # One query for the rows, one for the archetypes, three for the pools and the two card-set bounds
  # `StandardPool#name` reads: five once a list plays the card in a Standard pool, two when it is
  # played only outside Standard (no pool to load), one when no list plays it. On a production copy the widest card (Boss's Orders, 82 archetypes, 1104 played
  # (archetype, tournament) pairs) reads 4606 rows in 46.6 ms. See
  # docs/superpowers/specs/2026-11-25-card-archetype-usage-design.md.
  class ArchetypeUsage < ApplicationService
    ALL = Archetypes::MetagameScope::ALL
    VENUES = %w[all paper online].freeze
    OTHER_FORMATS_LABEL = "Other formats".freeze

    # `min_copies`/`max_copies`/`modes` are over the lists that play the card — the range *when
    # played*, as `CardStats::Entry` reports it — and nil/nil/[] when none does. The predicate
    # names are `Entry`'s, because `Archetypes::CopiesText` prints either.
    Usage = Struct.new(:lists_count, :playing_count, :pct, :min_copies, :max_copies, :modes,
                       keyword_init: true) do
      def played? = playing_count.positive?
      def single_quantity? = min_copies == max_copies
      def tied_mode? = modes.size > 1
    end

    TournamentNode = Struct.new(:tournament_id, :label, :usage, :analysis_params, keyword_init: true)

    # `pool_id` nil is the "Other formats" node: the events no Standard pool anchors — Expanded,
    # GLC, and the Japanese Standard events, which are filed as `other` (measured on a production
    # copy: four "Standard (JP)" events). The analysis offers no sample of exactly those, so the
    # node carries no `analysis_params` and links nowhere — its figure is true, it simply has no
    # page to agree with.
    PoolNode = Struct.new(:pool_id, :label, :usage, :tournaments, :unplayed_tournaments_count,
                          :analysis_params, keyword_init: true)

    # The archetype's line for the selected sample, and what opens under it: its pools under All
    # formats, its played events under one pool (`pools` empty), nothing under one tournament
    # (both empty — the node is a leaf). `scope_label` names a sample the line's own name does
    # not: "All formats", the pool's name, or nil under a tournament, which its select names.
    ArchetypeNode = Struct.new(:archetype, :usage, :scope_label, :pools, :tournaments,
                               :unplayed_tournaments_count, :analysis_params, keyword_init: true)
    Option = Struct.new(:value, :label, keyword_init: true)

    # `pool` is the StandardPool selected, nil for All formats; `tournament_id` the event selected,
    # nil for every one. Both are the resolved values, never the parameters, so the selects and
    # the tree cannot disagree.
    Result = Struct.new(:pool, :pool_options, :pool_selectable,
                        :venue, :venue_options, :venue_selectable,
                        :tournament_id, :tournament_options, :tournament_selectable,
                        :archetypes, keyword_init: true) do
      # Each control is a genuine choice or it is not rendered, the three rules of
      # `MetagameScope::Result`: two pool options, or one plus a playing list outside Standard (one
      # pool alone is the same sample as All formats); playing lists under both venues (`venue_options`
      # always number three); two played events or more.
      def pool_selectable? = pool_selectable
      def venue_selectable? = venue_selectable
      def tournament_selectable? = tournament_selectable
      def any? = archetypes.any?
    end

    Row = Struct.new(:archetype_id, :pool_id, :online, :tournament_id, :tournament_name,
                     :tournament_date, :deck_id, :copies, keyword_init: true)

    # Every parameter is whatever arrived in the query string — an Array or a Hash among the
    # possibilities on a public page — so `to_s` first, then compared as a String against the
    # values offered, never through `to_i`, which reads "12junk" as 12.
    def initialize(card:, pool_param: nil, venue_param: nil, tournament_param: nil)
      @card = card
      @pool_param = pool_param.to_s
      @venue_param = venue_param.to_s
      @tournament_param = tournament_param.to_s
    end

    def call
      pool = selected_pool
      pool_rows = rows_in_pool(pool)
      venue = selected_venue(pool_rows)
      venue_rows = rows_in_venue(pool_rows, venue)
      tournament_id = selected_tournament(venue_rows)

      Result.new(
        pool: pool,
        pool_options: pool_options,
        pool_selectable: pool_selectable?,
        venue: venue,
        venue_options: venue_options(pool_rows),
        venue_selectable: playing?(rows_in_venue(pool_rows, :paper)) && playing?(rows_in_venue(pool_rows, :online)),
        tournament_id: tournament_id,
        tournament_options: tournament_options(venue_rows),
        tournament_selectable: tournament_selectable?(venue_rows),
        archetypes: archetype_nodes(pool, venue, venue_rows, tournament_id)
      )
    end

    private

    # Every listed standing of every archetype holding at least one list that plays the card, with
    # that list's copies of it (nil when it plays none). One row per standing: two printings of the
    # card in one deck are summed by the subquery's GROUP BY, so the LEFT JOIN matches one row per
    # deck, and a deck at two events is two rows that the deck-id sets below count once per node.
    # No DISTINCT — it was here once, and a mutation removing it changed no figure.
    def rows
      @rows ||= begin
        plays = card_rows.group(:deck_id)
                         .select("deck_cards.deck_id AS deck_id, SUM(deck_cards.quantity) AS copies")
        played_archetypes = TournamentStanding.where(deck_id: card_rows.select(:deck_id))
                                              .select(:archetype_id)

        TournamentStanding
          .where.not(deck_id: nil)
          .where(archetype_id: played_archetypes)
          .joins(:tournament)
          .joins("LEFT JOIN (#{plays.to_sql}) plays ON plays.deck_id = tournament_standings.deck_id")
          .pluck(
            :archetype_id, Arel.sql("tournaments.standard_pool_id"), Arel.sql("tournaments.online"),
            :tournament_id, Arel.sql("tournaments.name"), Arel.sql("tournaments.date"),
            :deck_id, Arel.sql("plays.copies")
          )
          .map do |archetype_id, pool_id, online, tournament_id, name, date, deck_id, copies|
            Row.new(archetype_id: archetype_id, pool_id: pool_id, online: online,
                    tournament_id: tournament_id, tournament_name: name,
                    tournament_date: date.is_a?(String) ? Date.parse(date) : date,
                    deck_id: deck_id, copies: copies)
          end
      end
    end

    # The card's `deck_cards`, keyed as `CardStats::GROUPING_KEY` keys them: by fingerprint, or —
    # for a card that has none — by its own id alone, never folded with another unfingerprinted
    # card of the same name.
    def card_rows
      scope = DeckCard.joins(:card)
      if @card.fingerprint.present?
        scope.where(cards: { fingerprint: @card.fingerprint })
      else
        scope.where(card_id: @card.id)
      end
    end

    # The pool selection: one Standard pool's rows, or every row under All formats.
    def rows_in_pool(pool)
      pool ? rows.select { |row| row.pool_id == pool.id } : rows
    end

    def rows_in_venue(sample, venue)
      return sample if venue == :all

      sample.select { |row| row.online == (venue == :online) }
    end

    def playing?(sample)
      sample.any?(&:copies)
    end

    # The pools a list plays the card in, any venue, most recent playing event first and the pool
    # id breaking a tie. Over both venues on purpose, so a pool's label does not move when a venue
    # is chosen — the analysis's stable-label rule (`MetagameScope#options`), which the clamp in
    # `selected_venue` keeps honest.
    def played_pools
      @played_pools ||= rows.select(&:copies).reject { |row| row.pool_id.nil? }.group_by(&:pool_id)
                            .sort_by { |pool_id, pool_rows| [ pool_rows.map(&:tournament_date).max, pool_id ] }
                            .reverse
                            .map { |pool_id, pool_rows| [ pools.fetch(pool_id), pool_rows ] }
    end

    def pool_options
      played_pools.map do |pool, pool_rows|
        Option.new(value: pool.id.to_s, label: "#{pool.name} — #{lists_label(playing_decks(pool_rows).size)}")
      end + [ Option.new(value: ALL, label: "All formats — #{lists_label(playing_decks(rows).size)}") ]
    end

    def pool_selectable?
      played_pools.size > 1 || (played_pools.size == 1 && rows.any? { |row| row.copies && row.pool_id.nil? })
    end

    # All formats unless the parameter names a pool on offer, and only while the control is
    # rendered: a page must not pin a filter it offers no way to remove.
    def selected_pool
      return nil unless pool_selectable?

      played_pools.map(&:first).find { |pool| pool.id.to_s == @pool_param }
    end

    # A venue in which no list plays the card inside the pool selection falls back to `:all` — the
    # clamp, recorded in the Result so the select and the tree cannot disagree.
    def selected_venue(pool_rows)
      return :all unless VENUES.include?(@venue_param)

      venue = @venue_param.to_sym
      return :all if venue != :all && !playing?(rows_in_venue(pool_rows, venue))

      venue
    end

    # Counted inside the pool selection, as the analysis counts its venue options.
    def venue_options(pool_rows)
      VENUES.map do |value|
        lists = playing_decks(rows_in_venue(pool_rows, value.to_sym)).size
        Option.new(value: value, label: "#{value.capitalize} — #{lists_label(lists)}")
      end
    end

    # The events of the pool + venue selection where a list plays the card, newest first, the id
    # breaking a tie.
    def played_events(venue_rows)
      venue_rows.select(&:copies).group_by(&:tournament_id)
                .sort_by { |tournament_id, event_rows| [ event_rows.first.tournament_date, tournament_id ] }
                .reverse
    end

    def tournament_options(venue_rows)
      [ Option.new(value: ALL, label: "All tournaments — #{lists_label(playing_decks(venue_rows).size)}") ] +
        played_events(venue_rows).map do |tournament_id, event_rows|
          Option.new(value: tournament_id.to_s,
                     label: "#{event_label(event_rows.first)} — #{lists_label(playing_decks(event_rows).size)}")
        end
    end

    def tournament_selectable?(venue_rows)
      played_events(venue_rows).size > 1
    end

    def selected_tournament(venue_rows)
      return nil unless tournament_selectable?(venue_rows)

      played_events(venue_rows).map(&:first).find { |tournament_id| tournament_id.to_s == @tournament_param }
    end

    def playing_decks(sample)
      sample.select(&:copies).map(&:deck_id).to_set
    end

    def lists_label(count)
      "#{count} #{'list'.pluralize(count)} with this card"
    end

    # Labelled the way `TournamentEntry#picker_label` and the analysis's Tournament select print an
    # event, because the name alone is not an identity (55 events share theirs).
    def event_label(row)
      "#{row.tournament_name} (#{I18n.l(row.tournament_date)})"
    end

    # The analysis's denominator is distinct deck ids; its numerator distinct decks playing the
    # key; its copies the per-deck sum, taken once per deck.
    def usage_for(sample)
      lists = sample.map(&:deck_id).to_set.size
      copies = sample.select(&:copies).uniq(&:deck_id).map(&:copies)
      playing = copies.size

      Usage.new(
        lists_count: lists,
        playing_count: playing,
        pct: lists.zero? ? 0.0 : (100.0 * playing / lists).round(1),
        min_copies: copies.min,
        max_copies: copies.max,
        modes: copies.empty? ? [] : Archetypes::CardStats.modes_of(copies)
      )
    end

    # Archetypes playing the card in the selected sample, most lists playing it first, then by
    # name. What opens under each follows the selection: its pools under All formats, its events
    # under one pool, nothing under one tournament.
    def archetype_nodes(pool, venue, venue_rows, tournament_id)
      sample_rows = tournament_id ? venue_rows.select { |row| row.tournament_id == tournament_id } : venue_rows
      by_archetype = sample_rows.group_by(&:archetype_id)
      archetypes = Archetype.where(id: by_archetype.keys).index_by(&:id)

      by_archetype.filter_map do |archetype_id, sample|
        usage = usage_for(sample)
        next unless usage.played?

        archetype_node(archetypes.fetch(archetype_id), usage, pool, venue, sample, tournament_id)
      end.sort_by { |node| [ -node.usage.playing_count, node.archetype.name.to_s, node.archetype.id ] }
    end

    def archetype_node(archetype, usage, pool, venue, sample, tournament_id)
      pool_value = pool ? pool.id.to_s : Archetypes::MetagameScope::ALL
      node = ArchetypeNode.new(archetype: archetype, usage: usage, pools: [], tournaments: [],
                               unplayed_tournaments_count: 0)

      if tournament_id
        node.analysis_params = with_venue({ pool: pool_value, tournament: tournament_id.to_s }, venue)
      elsif pool
        events = pool_node(venue, pool.id, pool.name, sample, nil)
        node.scope_label = pool.name
        node.tournaments = events.tournaments
        node.unplayed_tournaments_count = events.unplayed_tournaments_count
        node.analysis_params = with_venue({ pool: pool_value }, venue)
      else
        node.scope_label = "All formats"
        node.pools = pool_nodes(venue, sample)
        node.analysis_params = with_venue({ pool: pool_value }, venue)
      end
      node
    end

    # Every pool the archetype has a list in — 0 % included, since a card dropped after a
    # rotation is an answer — most recent event first and the pool id breaking a tie, the
    # analysis's own order. The non-Standard events close the list as one node.
    def pool_nodes(venue, sample)
      grouped = sample.group_by(&:pool_id)
      standard = grouped.except(nil).sort_by do |pool_id, pool_rows|
        [ pool_rows.map(&:tournament_date).max, pool_id ]
      end.reverse

      nodes = standard.map do |pool_id, pool_rows|
        pool_node(venue, pool_id, pools.fetch(pool_id).name, pool_rows,
                  with_venue({ pool: pool_id.to_s }, venue))
      end
      if grouped.key?(nil)
        nodes << pool_node(venue, nil, OTHER_FORMATS_LABEL, grouped[nil], nil)
      end
      nodes
    end

    def pool_node(venue, pool_id, label, pool_rows, analysis_params)
      by_tournament = pool_rows.group_by(&:tournament_id)
      played = by_tournament.select { |_id, event_rows| event_rows.any?(&:copies) }

      PoolNode.new(
        pool_id: pool_id,
        label: label,
        usage: usage_for(pool_rows),
        tournaments: tournament_nodes(venue, pool_id, played),
        unplayed_tournaments_count: by_tournament.size - played.size,
        analysis_params: analysis_params
      )
    end

    # Played events only, newest first, the id breaking a tie, labelled as `event_label` says.
    def tournament_nodes(venue, pool_id, played)
      played.map do |tournament_id, event_rows|
        first = event_rows.first
        TournamentNode.new(
          tournament_id: tournament_id,
          label: event_label(first),
          usage: usage_for(event_rows),
          analysis_params: with_venue(
            { pool: pool_id ? pool_id.to_s : Archetypes::MetagameScope::ALL, tournament: tournament_id.to_s },
            venue
          )
        )
      end.sort_by { |node| [ played[node.tournament_id].first.tournament_date, node.tournament_id ] }.reverse
    end

    def with_venue(params, venue)
      venue == :all ? params : params.merge(venue: venue.to_s)
    end

    # `named` preloads both bounds, which StandardPool#name reads.
    def pools
      @pools ||= StandardPool.named.where(id: rows.filter_map(&:pool_id).uniq).index_by(&:id)
    end
  end
end
