module Decks
  class CardAdder < ApplicationService
    def initialize(deck:, card:, quantity: 1)
      @deck = deck
      @card = card
      @quantity = quantity
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
      free_for_deck = Allocations::Availability.call(user: @deck.user, card: @card, excluding_deck: @deck).available

      Allocations::Backing.greedy(
        quantity: deck_card.quantity, current_owned: deck_card.owned_copies.to_i, available: free_for_deck
      )
    end
  end
end
