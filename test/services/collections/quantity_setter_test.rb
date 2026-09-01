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
      deck = user.decks.create!(name: "A", physical: true, standard_pool: standard_pools(:twm_por))
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

    # Targets the "unknown" variant while a "fr" row exists, and asserts the whole
    # post-state. Both halves are load-bearing: the widened unique index orders
    # rows by (language, finish), and every real variant of an international set
    # sorts before "unknown" — so a service that dropped the variant from its
    # lookup would land on "fr", and a test targeting "fr" would call that
    # correct.
    test "sets one variant without touching the others" do
      user = users(:one)
      card = cards(:honedge) # fixture: quantity 1, unknown/unknown
      Collections::CardAdder.call(user: user, card: card, quantity: 4, language: "fr")

      collection = Collections::QuantitySetter.call(user: user, card: card, quantity: 2)

      assert_equal 2, collection.quantity
      assert_equal [ [ "fr", "unknown", 4 ], [ "unknown", "unknown", 2 ] ],
        user.collections.where(card: card).order(:language, :finish).pluck(:language, :finish, :quantity)
    end
  end
end
