module Collections
  # Sets a user's owned quantity for a card to an exact value. Reducing below
  # what physical decks currently commit is allowed and leaves those decks
  # over-allocated (surfaced elsewhere, never blocked here).
  class QuantitySetter < ApplicationService
    def initialize(user:, card:, quantity:)
      @user = user
      @card = card
      @quantity = quantity
    end

    def call
      collection = @user.collections.find_or_initialize_by(card: @card)
      collection.update!(quantity: @quantity)
      collection
    end
  end
end
