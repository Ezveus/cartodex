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

    def call
      Result.new(owned: owned, committed: committed, available: [ owned - committed_excluding, 0 ].max)
    end

    private

    # Memoised because each of these is asked for more than once while building
    # the Result. Rails' query cache already absorbs the duplicates, so this
    # saves cache lookups rather than round trips — cheap, and it keeps the
    # reader from assuming a second query happens.
    def owned
      @owned ||= @user.collections.where(card: @card).sum(:quantity)
    end

    def committed
      @committed ||= physical_deck_cards.sum(:owned_copies)
    end

    def committed_excluding
      return committed unless @excluding_deck

      @committed_excluding ||= physical_deck_cards.where.not(deck_id: @excluding_deck.id).sum(:owned_copies)
    end

    def physical_deck_cards
      DeckCard.where(card: @card, deck_id: @user.decks.where(physical: true).select(:id))
    end
  end
end
