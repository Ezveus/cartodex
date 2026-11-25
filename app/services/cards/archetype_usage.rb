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
  # One query for the rows, one for the archetypes, one for the pools: three whatever the card. On
  # a production copy the widest card (Boss's Orders, 82 archetypes, 1104 played (archetype,
  # tournament) pairs) reads 4606 rows in 46.6 ms. See
  # docs/superpowers/specs/2026-11-25-card-archetype-usage-design.md.
  class ArchetypeUsage < ApplicationService
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

    ArchetypeNode = Struct.new(:archetype, :usage, :pools, :analysis_params, keyword_init: true)
    Option = Struct.new(:value, :label, keyword_init: true)

    Result = Struct.new(:venue, :venue_options, :venue_selectable, :archetypes, keyword_init: true) do
      # True when lists playing the card exist under both venues. Not `venue_options.size > 1`,
      # which is always three: "All" beside the one venue holding every list is two labels over one
      # sample, the non-choice `MetagameScope::Result#venue_selectable?` refuses too.
      def venue_selectable? = venue_selectable
      def any? = archetypes.any?
    end

    Row = Struct.new(:archetype_id, :pool_id, :online, :tournament_id, :tournament_name,
                     :tournament_date, :deck_id, :copies, keyword_init: true)

    # `venue_param` is whatever arrived in the query string — an Array or a Hash among the
    # possibilities on a public page — so `to_s` first, then `VENUES.include?`.
    def initialize(card:, venue_param: nil)
      @card = card
      @venue_param = venue_param.to_s
    end

    def call
      venue = selected_venue
      venue_rows = rows_in(venue)

      Result.new(
        venue: venue,
        venue_options: venue_options,
        venue_selectable: playing_in?(:paper) && playing_in?(:online),
        archetypes: archetype_nodes(venue, venue_rows)
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

    def rows_in(venue)
      return rows if venue == :all

      rows.select { |row| row.online == (venue == :online) }
    end

    def playing_in?(venue)
      rows_in(venue).any?(&:copies)
    end

    # A venue in which no list plays the card falls back to `:all` — the clamp, recorded in the
    # Result so the select and the tree cannot disagree.
    def selected_venue
      return :all unless VENUES.include?(@venue_param)

      venue = @venue_param.to_sym
      return :all if venue != :all && !playing_in?(venue)

      venue
    end

    def venue_options
      VENUES.map do |value|
        lists = playing_decks(rows_in(value.to_sym)).size
        Option.new(value: value,
                   label: "#{value.capitalize} — #{lists} #{'list'.pluralize(lists)} with this card")
      end
    end

    def playing_decks(sample)
      sample.select(&:copies).map(&:deck_id).to_set
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

    # Archetypes playing the card in this venue, most lists playing it first, then by name.
    def archetype_nodes(venue, venue_rows)
      by_archetype = venue_rows.group_by(&:archetype_id)
      archetypes = Archetype.where(id: by_archetype.keys).index_by(&:id)

      by_archetype.filter_map do |archetype_id, sample|
        usage = usage_for(sample)
        next unless usage.played?

        archetype = archetypes.fetch(archetype_id)
        ArchetypeNode.new(
          archetype: archetype,
          usage: usage,
          pools: pool_nodes(venue, sample),
          analysis_params: with_venue({ pool: Archetypes::MetagameScope::ALL }, venue)
        )
      end.sort_by { |node| [ -node.usage.playing_count, node.archetype.name.to_s, node.archetype.id ] }
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

    # Played events only, newest first, the id breaking a tie. Labelled the way
    # `TournamentEntry#picker_label` and the analysis's Tournament select print an event, because
    # the name alone is not an identity (55 events share theirs).
    def tournament_nodes(venue, pool_id, played)
      played.map do |tournament_id, event_rows|
        first = event_rows.first
        TournamentNode.new(
          tournament_id: tournament_id,
          label: "#{first.tournament_name} (#{I18n.l(first.tournament_date)})",
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
