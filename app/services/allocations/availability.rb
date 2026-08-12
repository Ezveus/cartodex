module Allocations
  # Computes, for one user and one exact printing (card), how many copies are
  # owned, how many are committed as real copies across physical decks, and how
  # many remain available. `excluding_deck` drops that deck's own committed
  # copies from the total, yielding the pool that deck may (re)claim.
  class Availability < ApplicationService
    Result = Struct.new(:owned, :committed, :available, keyword_init: true)

    # The same three numbers for many cards at once, as a Hash of card id =>
    # Result. Callers that render a whole collection or decklist must use this:
    # `call` costs two queries per card, so a per-row loop is an N+1 that grows
    # with the user's collection, while this stays at two grouped queries (three
    # when a deck is excluded) whatever the card count.
    #
    # Cards the user does not own are present in the Hash with zeroes, so a
    # caller never has to distinguish "absent" from "none owned".
    def self.for_cards(user:, cards:, excluding_deck: nil)
      # Sorted so that the same set of cards always produces byte-identical SQL,
      # whatever order the caller collected them in. A page that also builds an
      # over-allocation report asks for the same ids, and identical SQL lets
      # Rails' query cache serve the second ask instead of hitting the database.
      card_ids = Array(cards).map(&:id).uniq.sort
      return {} if card_ids.empty?

      owned_by_card = user.collections.where(card_id: card_ids).group(:card_id).sum(:quantity)
      committed_scope = DeckCard.where(card_id: card_ids, deck_id: user.decks.where(physical: true).select(:id))
      committed_by_card = committed_scope.group(:card_id).sum(:owned_copies)
      claimable_by_card = if excluding_deck
        committed_scope.where.not(deck_id: excluding_deck.id).group(:card_id).sum(:owned_copies)
      else
        committed_by_card
      end

      card_ids.index_with do |card_id|
        owned = owned_by_card[card_id] || 0
        Result.new(
          owned: owned,
          committed: committed_by_card[card_id] || 0,
          available: [ owned - (claimable_by_card[card_id] || 0), 0 ].max
        )
      end
    end

    def initialize(user:, card:, excluding_deck: nil)
      @user = user
      @card = card
      @excluding_deck = excluding_deck
    end

    # Delegates to for_cards rather than re-deriving the same three numbers: one
    # card is just the smallest batch, and it costs the same two grouped queries
    # (three when a deck is excluded). Keeping a second implementation here meant
    # the owned/committed/available rule was written twice, so a change to it
    # could leave the per-card and the batched answers disagreeing.
    def call
      self.class.for_cards(user: @user, cards: [ @card ], excluding_deck: @excluding_deck).fetch(@card.id)
    end
  end
end
