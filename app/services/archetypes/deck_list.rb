module Archetypes
  # The decks of one archetype, as the archetype's front page lists them: the reader's own first,
  # then every public one, a page at a time.
  #
  # **Which decks belong, and why two columns decide it.** A member's deck belongs to the archetype
  # its `decks.archetype_id` names — the member chose it. A field list (ownerless, created from a
  # standings row) belongs to the archetype of its **standing**, never to its own column: that
  # column was written by Decks::ArchetypeDetector at import, and measured on a production copy it
  # contradicts the standing on 405 of 1223 field lists (37 *Slowking* lists tagged *Lillie's
  # Clefairy ex*, 62 *Dragapult ex* tagged *Dragapult ex / Dusknoir*). The standing is what an admin
  # confirmed and what Archetypes::MetagameScope counts, so reading it keeps this list and the
  # analysis one click away describing the same lists. #195 realigns the column; #196 then moves
  # this service onto it alone.
  #
  # Variants are not folded in: a parent's page lists the parent's decks, the way MetagameScope
  # counts the parent's standings.
  class DeckList < ApplicationService
    PER_PAGE = 24

    # `standings` maps a listed deck's id to the one standing that put it on this page — see
    # #listing_standings. Only field lists have one.
    Result = Data.define(:own_decks, :decks, :page, :pages, :total, :standings) do
      def caption_for(deck) = DeckList.caption(standings[deck.id])
    end

    # What each card on the page reads: the card count, the format badge (the pool's name reads
    # both bounds — see Deck.with_standard_pool) and the type stripe (the deck's archetype's member
    # cards). The caption's standing is loaded apart, by #listing_standings.
    PRELOADS = [ :deck_cards, { archetype: [ :primary_card, :secondary_card ] } ].freeze

    # **One standing per deck, and it is this archetype's.** index_tournament_standings_on_deck_id
    # is not unique: two standings may point at one deck (two players registering the same sixty
    # cards), and they need not be filed under one archetype. The deck is listed here because of the
    # standings filed under *this* archetype, so those are the only ones it is sorted and captioned
    # by — read across all of them, a deck listed for placing 40th at this archetype's event was
    # captioned "1st" at an event where it was filed as another. Among this archetype's, the most
    # recent event wins, then the best placement, then the newest standing: STANDING_ORDER in SQL
    # for the sort, #listing_standings in Ruby for the caption, the same rule twice so the caption
    # always names the row the deck was sorted by.
    #
    # Correlated subqueries rather than a JOIN, for the same non-unique index: a JOIN would list and
    # count the deck once per standing. A deck with no standing — a member's shared deck — sorts at
    # the day it was created. `decks.id DESC` makes the order total, so a page boundary cannot move
    # between two requests.
    STANDING_ORDER = "tournaments.date DESC, tournament_standings.placement ASC NULLS LAST, " \
                     "tournament_standings.id DESC".freeze

    def self.caption(standing)
      return nil if standing.nil?

      event = standing.tournament.name
      event = "#{event} — #{standing.placement.ordinalize}" if standing.placement
      "#{event} · #{standing.division.humanize}"
    end

    def initialize(archetype:, viewer:, page:)
      @archetype = archetype
      @viewer = viewer
      @page = page
    end

    def call
      scope = public_scope
      total = scope.count
      pages = (total / PER_PAGE.to_f).ceil
      page = @page.clamp(1, [ pages, 1 ].max)

      decks = scope.order(order).offset((page - 1) * PER_PAGE).limit(PER_PAGE)
                   .with_standard_pool.includes(*PRELOADS).to_a

      Result.new(own_decks: own_decks, decks: decks, page: page, pages: pages, total: total,
                 standings: listing_standings(decks))
    end

    private

    def order
      Arel.sql(ActiveRecord::Base.sanitize_sql_array([ <<~SQL.squish, @archetype.id, @archetype.id ]))
        COALESCE(#{standing_key("tournaments.date")}, date(decks.created_at)) DESC,
        #{standing_key("tournament_standings.placement")} ASC NULLS LAST,
        decks.id DESC
      SQL
    end

    # One column of the deck's listing standing. Both keys select through the same ORDER BY … LIMIT
    # 1, so the date and the placement always come from one row — MAX(date) beside MIN(placement)
    # can take them from two.
    def standing_key(column)
      <<~SQL.squish
        (SELECT #{column} FROM tournament_standings
           JOIN tournaments ON tournaments.id = tournament_standings.tournament_id
          WHERE tournament_standings.deck_id = decks.id AND tournament_standings.archetype_id = ?
          ORDER BY #{STANDING_ORDER} LIMIT 1)
      SQL
    end

    # The Ruby half of STANDING_ORDER, over one query for the whole page.
    def listing_standings(decks)
      TournamentStanding.where(archetype_id: @archetype.id, deck_id: decks.map(&:id))
                        .includes(:tournament).to_a
                        .group_by(&:deck_id)
                        .transform_values do |standings|
                          standings.min_by { |s| [ -s.tournament.date.jd, s.placement || Float::INFINITY, -s.id ] }
                        end
    end

    # `where(id: …)` over a subquery, not a JOIN, for the reason STANDING_ORDER's comment gives — and it is the faster
    # form too: measured on the production copy for the largest archetype (174 decks), 0.3 ms
    # against 0.9 ms, the subquery searching index_tournament_standings_on_archetype_id where the
    # JOIN scanned every shared deck.
    def public_scope
      field_list_ids = TournamentStanding.where(archetype_id: @archetype.id)
                                         .where.not(deck_id: nil).select(:deck_id)

      scope = Deck.shared.where(user_id: nil, id: field_list_ids)
                  .or(Deck.shared.where.not(user_id: nil).where(archetype_id: @archetype.id))
      return scope if @viewer.nil?

      # Spelled with an explicit `user_id IS NULL` branch. `where.not(user_id: viewer)` alone is
      # `user_id != ?`, which SQL evaluates to NULL — not true — for every field list, and would
      # empty the list for any signed-in reader: the trap Search::Global#shared_deck_scope fell
      # into once.
      #
      # `and`, not `merge`: both sides constrain `user_id`, and `merge` replaces a condition on a
      # column the receiver already constrains rather than conjoining it.
      scope.and(Deck.where(user_id: nil).or(Deck.where.not(user_id: @viewer.id)))
    end

    # Private and shared alike, since they are the reader's own; a handful at most (43 private
    # tagged decks in the whole production copy), so no page.
    def own_decks
      return [] if @viewer.nil?

      @viewer.decks.where(archetype_id: @archetype.id).order(:name)
             .with_standard_pool.includes(*PRELOADS).to_a
    end
  end
end
