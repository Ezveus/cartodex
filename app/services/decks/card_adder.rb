module Decks
  class CardAdder < ApplicationService
    # `available` is the pool this deck may claim for this card, when the caller has already read
    # it. Decks::BulkCardAdder passes it because it reads the whole batch's availability in one
    # grouped query; every other caller leaves it nil and this service reads its own. Passing it
    # does not change the rule — Allocations::Backing.greedy is still what decides — only who paid
    # for the number.
    def initialize(deck:, card:, quantity: 1, available: nil)
      @deck = deck
      @card = card
      @quantity = quantity
      @available = available
    end

    def call
      serialized_transaction do
        deck_card = @deck.deck_cards.find_or_initialize_by(card: @card)
        deck_card.quantity = deck_card.quantity.to_i + @quantity
        deck_card.owned_copies = target_owned_copies(deck_card) if @deck.physical?
        deck_card.save!
        deck_card
      end
    end

    private

    # Greedy backing, the rule in Allocations::Backing: an add never demotes existing reals.
    def target_owned_copies(deck_card)
      free_for_deck =
        @available || Allocations::Availability.call(user: @deck.user, card: @card, excluding_deck: @deck).available

      Allocations::Backing.greedy(
        quantity: deck_card.quantity, current_owned: deck_card.owned_copies.to_i, available: free_for_deck
      )
    end
  end
end
