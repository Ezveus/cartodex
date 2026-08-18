module Collections
  class CardAdder < ApplicationService
    # language and finish default to the "unknown" sentinel, so every existing
    # caller — the webcam scan, the card page's +, AddCardToCollectionTool —
    # keeps working untouched and keeps getting one row per printing.
    def initialize(user:, card:, quantity: 1, language: "unknown", finish: "unknown")
      @user = user
      @card = card
      @quantity = quantity
      @language = language
      @finish = finish
    end

    def call
      serialized_transaction do
        collection = @user.collections.find_or_initialize_by(card: @card, language: @language, finish: @finish)
        collection.quantity = collection.quantity.to_i + @quantity
        collection.save!
        collection
      end
    end
  end
end
