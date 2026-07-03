require "test_helper"

module Allocations
  class AvailabilityTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      @card = cards(:honedge)
      @user.collections.find_or_create_by!(card: @card).update!(quantity: 3)
      @deck_a = @user.decks.create!(name: "A", physical: true)
      @deck_b = @user.decks.create!(name: "B", physical: true)
    end

    test "available equals owned when nothing is committed" do
      result = Allocations::Availability.call(user: @user, card: @card)
      assert_equal 3, result.owned
      assert_equal 0, result.committed
      assert_equal 3, result.available
    end

    test "committed sums owned_copies across physical decks; available is the remainder" do
      @deck_a.deck_cards.create!(card: @card, quantity: 2, owned_copies: 2)
      @deck_b.deck_cards.create!(card: @card, quantity: 1, owned_copies: 1)

      result = Allocations::Availability.call(user: @user, card: @card)
      assert_equal 3, result.committed
      assert_equal 0, result.available
    end

    test "excluding_deck frees that deck's own committed copies" do
      @deck_a.deck_cards.create!(card: @card, quantity: 2, owned_copies: 2)

      result = Allocations::Availability.call(user: @user, card: @card, excluding_deck: @deck_a)
      assert_equal 2, result.committed         # total committed still 2
      assert_equal 3, result.available         # but deck A's 2 are reclaimable → 3 free for A
    end

    test "non-physical decks do not count toward committed" do
      live = @user.decks.create!(name: "Live", physical: false)
      live.deck_cards.create!(card: @card, quantity: 4) # owned_copies forced 0

      result = Allocations::Availability.call(user: @user, card: @card)
      assert_equal 0, result.committed
      assert_equal 3, result.available
    end

    test "available floors at zero when over-allocated" do
      @deck_a.deck_cards.create!(card: @card, quantity: 3, owned_copies: 3)
      @user.collections.find_by(card: @card).update!(quantity: 2) # sold one

      result = Allocations::Availability.call(user: @user, card: @card)
      assert_equal 2, result.owned
      assert_equal 3, result.committed
      assert_equal 0, result.available
    end
  end
end
