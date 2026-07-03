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

    # Greedy backing: use as many reals as the collection makes available to
    # this deck, capped at the deck_card's total, and never below what the deck
    # already backs (an add never demotes existing reals).
    def target_owned_copies(deck_card)
      current = deck_card.owned_copies.to_i
      free_for_deck = Allocations::Availability.call(user: @deck.user, card: @card, excluding_deck: @deck).available
      [ deck_card.quantity, [ current, free_for_deck ].max ].min
    end
  end
end
