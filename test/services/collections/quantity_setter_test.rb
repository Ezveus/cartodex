require "test_helper"

module Collections
  class QuantitySetterTest < ActiveSupport::TestCase
    test "sets an exact owned quantity, creating the row" do
      user = users(:two)
      card = cards(:trainer_card)

      collection = Collections::QuantitySetter.call(user: user, card: card, quantity: 5)

      assert_equal 5, collection.quantity
    end

    test "can reduce below what is committed without raising (tolerated over-allocation)" do
      user = users(:one)
      card = cards(:honedge)
      user.collections.find_or_create_by!(card: card).update!(quantity: 3)
      deck = user.decks.create!(name: "A", physical: true)
      deck.deck_cards.create!(card: card, quantity: 3, owned_copies: 3)

      collection = Collections::QuantitySetter.call(user: user, card: card, quantity: 2)

      assert_equal 2, collection.quantity
    end

    test "rejects a negative quantity" do
      assert_raises(ActiveRecord::RecordInvalid) do
        Collections::QuantitySetter.call(user: users(:one), card: cards(:honedge), quantity: -1)
      end
    end

    test "setting quantity twice ends at the last value" do
      user = users(:two)
      card = cards(:trainer_card)
      Collections::QuantitySetter.call(user: user, card: card, quantity: 4)
      collection = Collections::QuantitySetter.call(user: user, card: card, quantity: 2)
      assert_equal 2, collection.quantity
    end

    test "defaults to the unknown variant" do
      collection = Collections::QuantitySetter.call(user: users(:two), card: cards(:trainer_card), quantity: 3)

      assert_equal [ "unknown", "unknown" ], [ collection.language, collection.finish ]
    end

    test "sets one variant without touching the others" do
      user = users(:one)
      card = cards(:honedge) # fixture: quantity 1, unknown/unknown
      Collections::CardAdder.call(user: user, card: card, quantity: 4, language: "fr")

      collection = Collections::QuantitySetter.call(user: user, card: card, quantity: 2, language: "fr")

      assert_equal 2, collection.quantity
      assert_equal 1, user.collections.find_by!(card: card, language: "unknown", finish: "unknown").quantity
    end
  end
end
