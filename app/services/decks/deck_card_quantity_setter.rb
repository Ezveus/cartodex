module Decks
  # Sets the total quantity of a card in a deck. quantity <= 0 removes the card.
  # Real copies are recapped to the new total but never auto-increased (use
  # Decks::CardAdder for greedy backing).
  class DeckCardQuantitySetter < ApplicationService
    def initialize(deck:, card:, quantity:)
      @deck = deck
      @card = card
      @quantity = quantity
    end

    def call
      deck_card = @deck.deck_cards.find_by(card: @card)

      if @quantity.to_i <= 0
        deck_card&.destroy!
        return nil
      end

      deck_card ||= @deck.deck_cards.build(card: @card)
      deck_card.quantity = @quantity
      deck_card.owned_copies = [ deck_card.owned_copies.to_i, @quantity ].min
      deck_card.save!
      deck_card
    end
  end
end
