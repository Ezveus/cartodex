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

    Result = Struct.new(
      :archetype, :standings, :listed_standings, :pool, :options,
      :lists_count, :standings_count,
      keyword_init: true
    ) do
      def all_formats? = pool.nil?
      def small_sample? = lists_count.positive? && lists_count < SMALL_SAMPLE
      def no_lists? = lists_count.zero?
      # One option means the archetype has at most one pool and there is nothing to choose
      # between; the view drops the control rather than rendering a select of one.
      def selectable? = options.size > 1
    end

    # `pool_param` is whatever arrived in the query string: a pool id, ALL, nil, or junk —
    # `params[:pool]` can be an Array or a Hash, neither of which responds to `to_i`, and this
    # action is reachable by anyone with a session. `to_s` first, then fall back to the default.
    def initialize(archetype:, pool_param: nil)
      @archetype = archetype
      @pool_param = pool_param.to_s
    end

    def call
      pool = selected_pool
      bucket = totals_for(pool)

      Result.new(
        archetype: @archetype,
        standings: standings_scope(pool),
        listed_standings: standings_scope(pool).where.not(deck_id: nil),
        pool: pool,
        options: options,
        lists_count: bucket.lists,
        standings_count: bucket.standings
      )
    end

    private

    Bucket = Struct.new(:pool_id, :standings, :lists, :last_on, keyword_init: true)

    # One grouped query, and every number the selector prints comes out of it: per Standard pool
    # (NULL for the non-Standard events, which carry no pool by design), how many standings this
    # archetype has, how many of them carry a list, and when its most recent event there was.
    #
    # COUNT(DISTINCT deck_id) rather than COUNT(*): NULLs are ignored by DISTINCT, so this is the
    # list count and the standings count in the same pass, without a second query or a filtered
    # relation.
    def buckets
      @buckets ||= TournamentStanding
        .where(archetype_id: @archetype.id)
        .joins(:tournament)
        .group("tournaments.standard_pool_id")
        .pluck(
          Arel.sql("tournaments.standard_pool_id"),
          Arel.sql("COUNT(*)"),
          Arel.sql("COUNT(DISTINCT tournament_standings.deck_id)"),
          Arel.sql("MAX(tournaments.date)")
        )
        .map do |pool_id, standings, lists, last_on|
          Bucket.new(pool_id: pool_id, standings: standings, lists: lists, last_on: to_date(last_on))
        end
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

    # Most recent first, because that is the order a player thinks in. The pool id breaks a tie so
    # two pools sharing a last event date cannot swap places between two loads of the same page.
    def pool_buckets
      @pool_buckets ||= buckets.reject { |bucket| bucket.pool_id.nil? }
                               .sort_by { |bucket| [ bucket.last_on, bucket.pool_id ] }
                               .reverse
    end

    # Every option carries its list count. Choosing between rotations without them is blind, and
    # the fullest sample is not always the most recent one — for the measured archetype the newest
    # pool holds 3 lists and the oldest 68.
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

    def standings_scope(pool)
      scope = TournamentStanding.where(archetype_id: @archetype.id)
      return scope if pool.nil?

      scope.joins(:tournament).where(tournaments: { standard_pool_id: pool.id })
    end

    def totals_for(pool)
      return total if pool.nil?

      buckets.find { |bucket| bucket.pool_id == pool.id } ||
        Bucket.new(pool_id: pool.id, standings: 0, lists: 0, last_on: nil)
    end

    def total
      @total ||= Bucket.new(
        pool_id: nil,
        standings: buckets.sum(&:standings),
        lists: buckets.sum(&:lists),
        last_on: buckets.filter_map(&:last_on).max
      )
    end
  end
end
