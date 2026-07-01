module Decks
  class CardAdder < ApplicationService
    def initialize(deck:, card:, quantity: 1)
      @deck = deck
      @card = card
      @quantity = quantity
    end

    def call
      deck_card = @deck.deck_cards.find_or_initialize_by(card: @card)
      deck_card.quantity = deck_card.quantity.to_i + @quantity
      deck_card.save!
      deck_card
    end
  end
end
