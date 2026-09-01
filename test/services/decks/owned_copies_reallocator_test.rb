require "test_helper"

module Decks
  class OwnedCopiesReallocatorTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      @card = cards(:honedge)
      @user.collections.find_or_create_by!(card: @card).update!(quantity: 3)
      @deck_a = @user.decks.create!(name: "A", physical: true, standard_pool: standard_pools(:twm_por))
      @deck_b = @user.decks.create!(name: "B", physical: true, standard_pool: standard_pools(:twm_por))
      @a = @deck_a.deck_cards.create!(card: @card, quantity: 4, owned_copies: 3)
      @b = @deck_b.deck_cards.create!(card: @card, quantity: 4, owned_copies: 0)
    end

    test "moves reals without changing deck sizes or global committed" do
      Decks::OwnedCopiesReallocator.call(from_deck: @deck_a, to_deck: @deck_b, card: @card, quantity: 1)

      assert_equal 4, @a.reload.quantity
      assert_equal 2, @a.owned_copies
      assert_equal 4, @b.reload.quantity
      assert_equal 1, @b.owned_copies
    end

    test "rejects when the source lacks enough reals" do
      assert_raises(ArgumentError) do
        Decks::OwnedCopiesReallocator.call(from_deck: @deck_a, to_deck: @deck_b, card: @card, quantity: 4)
      end
    end

    test "rejects when the target lacks proxy slots" do
      @b.update!(owned_copies: 4) # no proxy slots left (but this over-fills availability; set quantity room instead)
      @b.update!(quantity: 4, owned_copies: 4)
      assert_raises(ArgumentError) do
        Decks::OwnedCopiesReallocator.call(from_deck: @deck_a, to_deck: @deck_b, card: @card, quantity: 1)
      end
    end

    test "rejects a non-physical deck" do
      live = @user.decks.create!(name: "Live", physical: false, standard_pool: standard_pools(:twm_por))
      live.deck_cards.create!(card: @card, quantity: 4)
      assert_raises(Decks::OwnedCopiesReallocator::NotPhysicalError) do
        Decks::OwnedCopiesReallocator.call(from_deck: @deck_a, to_deck: live, card: @card, quantity: 1)
      end
    end

    test "rejects reallocating a deck to itself" do
      assert_raises(ArgumentError) do
        Decks::OwnedCopiesReallocator.call(from_deck: @deck_a, to_deck: @deck_a, card: @card, quantity: 1)
      end
      assert_equal 3, @deck_a.deck_cards.find_by(card: @card).owned_copies # unchanged
    end
  end
end
