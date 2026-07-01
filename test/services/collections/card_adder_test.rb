require "test_helper"

module Collections
  class CardAdderTest < ActiveSupport::TestCase
    test "creates a collection entry when none exists" do
      user = users(:two)
      card = cards(:trainer_card)

      collection = Collections::CardAdder.call(user: user, card: card, quantity: 2)

      assert_equal 2, collection.quantity
      assert_equal user, collection.user
      assert_equal card, collection.card
    end

    test "increments an existing collection entry" do
      user = users(:one) # fixture: collection(:one) is honedge, quantity 1
      card = cards(:honedge)

      collection = Collections::CardAdder.call(user: user, card: card, quantity: 3)

      assert_equal 4, collection.quantity
    end
  end
end
