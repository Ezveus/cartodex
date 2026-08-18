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

    test "sequential adds accumulate the owned quantity" do
      user = users(:two)
      card = cards(:trainer_card)
      Collections::CardAdder.call(user: user, card: card, quantity: 2)
      collection = Collections::CardAdder.call(user: user, card: card, quantity: 3)
      assert_equal 5, collection.quantity
    end

    test "defaults to the unknown variant" do
      collection = Collections::CardAdder.call(user: users(:two), card: cards(:trainer_card), quantity: 1)

      assert_equal [ "unknown", "unknown" ], [ collection.language, collection.finish ]
    end

    test "adds to the named variant, leaving the unknown row alone" do
      user = users(:one) # fixture: collection(:one) is honedge, quantity 1, unknown/unknown
      card = cards(:honedge)

      collection = Collections::CardAdder.call(
        user: user, card: card, quantity: 2, language: "fr", finish: "reverse_holo"
      )

      assert_equal 2, collection.quantity
      assert_equal 1, user.collections.find_by!(card: card, language: "unknown", finish: "unknown").quantity
      assert_equal 3, user.collections.where(card: card).sum(:quantity), "the owned total must be the sum of the variants"
    end

    # Every other variant test here also varies the language, so `finish` never
    # has to discriminate anything: dropping it from the upsert key left the file
    # green.
    test "finish alone distinguishes two rows of one printing" do
      user = users(:two)
      card = cards(:trainer_card)
      Collections::CardAdder.call(user: user, card: card, quantity: 1)

      collection = Collections::CardAdder.call(user: user, card: card, quantity: 2, finish: "reverse_holo")

      assert_equal 2, collection.quantity
      assert_equal 2, user.collections.where(card: card).count
      assert_equal 1, user.collections.find_by!(card: card, finish: "unknown").quantity
    end

    test "increments the matching variant rather than creating a second row for it" do
      user = users(:two)
      card = cards(:trainer_card)
      Collections::CardAdder.call(user: user, card: card, quantity: 1, language: "fr")

      collection = Collections::CardAdder.call(user: user, card: card, quantity: 2, language: "fr")

      assert_equal 3, collection.quantity
      assert_equal 1, user.collections.where(card: card, language: "fr").count
    end
  end
end
