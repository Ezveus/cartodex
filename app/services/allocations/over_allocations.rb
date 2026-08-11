module Allocations
  # Lists cards whose real copies committed across the user's physical decks
  # exceed the number owned (only reachable via a collection decrease).
  class OverAllocations < ApplicationService
    def initialize(user:)
      @user = user
    end

    # Three grouped queries whatever the collection's size: what is committed per
    # card, what is owned for those cards, and which decks hold real copies of
    # the ones that came out over-allocated. Each of the last two used to run
    # once per card, making this report an N+1 over the collection.
    def call
      physical_deck_ids = @user.decks.where(physical: true).select(:id)
      committed_by_card = DeckCard.where(deck_id: physical_deck_ids).group(:card_id).sum(:owned_copies)
      return [] if committed_by_card.empty?

      # Sorted for the same reason as in Availability.for_cards: a page that
      # renders availability asks this exact question, and identical SQL means the
      # query cache answers the second one.
      owned_by_card = @user.collections.where(card_id: committed_by_card.keys.sort).group(:card_id).sum(:quantity)
      over_allocated = committed_by_card.select { |card_id, committed| committed > owned_by_card.fetch(card_id, 0) }
      return [] if over_allocated.empty?

      decks_by_card = decks_holding_real_copies(over_allocated.keys)

      over_allocated.map do |card_id, committed|
        {
          card_id: card_id,
          owned: owned_by_card.fetch(card_id, 0),
          committed: committed,
          decks: decks_by_card.fetch(card_id, [])
        }
      end
    end

    private

    # Which physical decks hold at least one real copy of each given card, in one
    # query. SQL cannot return the nested shape, so the rows are grouped in Ruby.
    def decks_holding_real_copies(card_ids)
      rows = @user.decks.where(physical: true)
                  .joins(:deck_cards)
                  .where(deck_cards: { card_id: card_ids })
                  .where("deck_cards.owned_copies > 0")
                  .distinct
                  .pluck("deck_cards.card_id", "decks.id", "decks.name")

      rows.group_by(&:first).transform_values do |group|
        group.map { |(_card_id, deck_id, deck_name)| { id: deck_id, name: deck_name } }
      end
    end
  end
end
