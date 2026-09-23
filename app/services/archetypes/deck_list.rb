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

    Result = Data.define(:own_decks, :decks, :page, :pages, :total)

    # What each card on the page reads: the card count, the format badge (the pool's name reads
    # both bounds — see Deck.with_standard_pool), the type stripe (the deck's archetype's member
    # cards) and the caption (the standing and its event).
    PRELOADS = [ :deck_cards, { archetype: [ :primary_card, :secondary_card ] },
                 { tournament_standing: :tournament } ].freeze

    # Two correlated sort keys rather than a JOIN on tournament_standings:
    # index_tournament_standings_on_deck_id is not unique, and two standings may legitimately point
    # at one deck (two players registering the same sixty cards), so a JOIN would list that deck
    # twice and count it twice. A deck with no standing — a member's shared deck — sorts at the day
    # it was created. `decks.id DESC` makes the order total, so a page boundary cannot move between
    # two requests.
    ORDER = Arel.sql(<<~SQL.squish).freeze
      COALESCE(
        (SELECT MAX(tournaments.date) FROM tournament_standings
           JOIN tournaments ON tournaments.id = tournament_standings.tournament_id
          WHERE tournament_standings.deck_id = decks.id),
        date(decks.created_at)
      ) DESC,
      (SELECT MIN(tournament_standings.placement) FROM tournament_standings
        WHERE tournament_standings.deck_id = decks.id) ASC NULLS LAST,
      decks.id DESC
    SQL

    def self.caption_for(deck)
      standing = deck.tournament_standing
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

      decks = scope.order(ORDER).offset((page - 1) * PER_PAGE).limit(PER_PAGE)
                   .with_standard_pool.includes(*PRELOADS).to_a

      Result.new(own_decks: own_decks, decks: decks, page: page, pages: pages, total: total)
    end

    private

    # `where(id: …)` over a subquery, not a JOIN, for the reason ORDER gives — and it is the faster
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
