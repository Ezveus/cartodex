module Collections
  # Sets a user's owned quantity for one variant of a card to an exact value.
  # Reducing below what physical decks currently commit is allowed and leaves
  # those decks over-allocated (surfaced elsewhere, never blocked here) — and
  # since allocation counts the printing's variants together, so does that
  # comparison.
  class QuantitySetter < ApplicationService
    def initialize(user:, card:, quantity:, language: "unknown", finish: "unknown")
      @user = user
      @card = card
      @quantity = quantity
      @language = language
      @finish = finish
    end

    def call
      serialized_transaction do
        collection = @user.collections.find_or_initialize_by(card: @card, language: @language, finish: @finish)
        collection.update!(quantity: @quantity)
        collection
      end
    end
  end
end
