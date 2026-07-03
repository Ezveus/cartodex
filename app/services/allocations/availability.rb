module Allocations
  # Computes, for one user and one exact printing (card), how many copies are
  # owned, how many are committed as real copies across physical decks, and how
  # many remain available. `excluding_deck` drops that deck's own committed
  # copies from the total, yielding the pool that deck may (re)claim.
  class Availability < ApplicationService
    Result = Struct.new(:owned, :committed, :available, keyword_init: true)

    def initialize(user:, card:, excluding_deck: nil)
      @user = user
      @card = card
      @excluding_deck = excluding_deck
    end

    def call
      Result.new(owned: owned, committed: committed, available: [ owned - committed_excluding, 0 ].max)
    end

    private

    def owned
      @user.collections.where(card: @card).sum(:quantity)
    end

    def committed
      physical_deck_cards.sum(:owned_copies)
    end

    def committed_excluding
      scope = physical_deck_cards
      scope = scope.where.not(deck_id: @excluding_deck.id) if @excluding_deck
      scope.sum(:owned_copies)
    end

    def physical_deck_cards
      DeckCard.where(card: @card, deck_id: @user.decks.where(physical: true).select(:id))
    end
  end
end
