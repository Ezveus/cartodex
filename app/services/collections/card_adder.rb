module Collections
  class CardAdder < ApplicationService
    def initialize(user:, card:, quantity: 1)
      @user = user
      @card = card
      @quantity = quantity
    end

    def call
      collection = @user.collections.find_or_initialize_by(card: @card)
      collection.quantity = collection.quantity.to_i + @quantity
      collection.save!
      collection
    end
  end
end
