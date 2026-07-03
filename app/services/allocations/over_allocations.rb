module Allocations
  # Lists cards whose real copies committed across the user's physical decks
  # exceed the number owned (only reachable via a collection decrease).
  class OverAllocations < ApplicationService
    def initialize(user:)
      @user = user
    end

    def call
      physical_deck_ids = @user.decks.where(physical: true).select(:id)
      committed_by_card = DeckCard.where(deck_id: physical_deck_ids).group(:card_id).sum(:owned_copies)

      committed_by_card.filter_map do |card_id, committed|
        owned = @user.collections.where(card_id: card_id).sum(:quantity)
        next if committed <= owned

        decks = @user.decks.where(physical: true)
                     .joins(:deck_cards)
                     .where(deck_cards: { card_id: card_id })
                     .where("deck_cards.owned_copies > 0")
                     .distinct
        { card_id: card_id, owned: owned, committed: committed, decks: decks.map { |d| { id: d.id, name: d.name } } }
      end
    end
  end
end
