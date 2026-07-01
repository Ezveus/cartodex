module Decks
  class CardTransfer < ApplicationService
    Result = Struct.new(:collection_quantity, :deck_quantity, keyword_init: true)

    def initialize(user:, deck:, card:, direction:, quantity: 1)
      @user = user
      @deck = deck
      @card = card
      @direction = direction
      @quantity = quantity
    end

    def call
      unless %i[in out].include?(@direction)
        raise ArgumentError, "direction must be :in or :out, got #{@direction.inspect}"
      end

      ActiveRecord::Base.transaction do
        @direction == :in ? transfer_in : transfer_out
      end

      Result.new(collection_quantity: collection_quantity, deck_quantity: deck_quantity)
    end

    private

    def transfer_in
      collection = @user.collections.find_or_initialize_by(card: @card)
      collection.quantity = [ collection.quantity.to_i - @quantity, 0 ].max
      collection.save!

      Decks::CardAdder.call(deck: @deck, card: @card, quantity: @quantity)
    end

    def transfer_out
      deck_card = @deck.deck_cards.find_by(card: @card)
      if deck_card
        remaining = deck_card.quantity - @quantity
        remaining <= 0 ? deck_card.destroy! : deck_card.update!(quantity: remaining)
      end

      Collections::CardAdder.call(user: @user, card: @card, quantity: @quantity)
    end

    def collection_quantity
      @user.collections.find_by(card: @card)&.quantity || 0
    end

    def deck_quantity
      @deck.deck_cards.find_by(card: @card)&.quantity || 0
    end
  end
end
