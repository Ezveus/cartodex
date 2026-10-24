require "test_helper"

module Decks
  class OwnedCopiesSetterTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      @card = cards(:honedge)
      @user.collections.find_or_create_by!(card: @card).update!(quantity: 3)
      @deck = @user.decks.create!(name: "A", physical: true, standard_pool: standard_pools(:twm_por))
      @deck_card = @deck.deck_cards.create!(card: @card, quantity: 4, owned_copies: 3)
    end

    test "lowers the real count (demoting to proxy)" do
      dc = Decks::OwnedCopiesSetter.call(deck: @deck, card: @card, owned_copies: 1)
      assert_equal 1, dc.owned_copies
    end

    test "rejects exceeding the deck_card quantity" do
      assert_raises(ArgumentError) do
        Decks::OwnedCopiesSetter.call(deck: @deck, card: @card, owned_copies: 5)
      end
    end

    test "rejects exceeding availability (cannot create over-allocation)" do
      other = @user.decks.create!(name: "B", physical: true, standard_pool: standard_pools(:twm_por))
      other.deck_cards.create!(card: @card, quantity: 2, owned_copies: 2) # only 1 free for @deck

      assert_raises(ArgumentError) do
        Decks::OwnedCopiesSetter.call(deck: @deck, card: @card, owned_copies: 3)
      end
    end

    test "a delta moves the real count from the stored row" do
      dc = Decks::OwnedCopiesSetter.call(deck: @deck, card: @card, delta: -1)
      assert_equal 2, dc.owned_copies

      dc = Decks::OwnedCopiesSetter.call(deck: @deck, card: @card, delta: 1)
      assert_equal 3, dc.owned_copies
    end

    # A tab that rendered 3 real sends "−" after another tab brought the row to 0 real: an absolute
    # 2 would claim two reals; the delta is refused against the stored 0.
    test "a stale − is refused against the stored value rather than claiming" do
      @deck_card.update!(owned_copies: 0)

      error = assert_raises(ArgumentError) { Decks::OwnedCopiesSetter.call(deck: @deck, card: @card, delta: -1) }
      assert_equal "owned_copies must be between 0 and 3", error.message
      assert_equal 0, @deck_card.reload.owned_copies
    end

    test "a delta past the bound is refused" do
      error = assert_raises(ArgumentError) { Decks::OwnedCopiesSetter.call(deck: @deck, card: @card, delta: 1) }
      assert_equal "owned_copies must be between 0 and 3", error.message
      assert_equal 3, @deck_card.reload.owned_copies
    end

    test "exactly one of owned_copies and delta, and an integer delta" do
      assert_raises(ArgumentError) { Decks::OwnedCopiesSetter.call(deck: @deck, card: @card) }
      assert_raises(ArgumentError) { Decks::OwnedCopiesSetter.call(deck: @deck, card: @card, owned_copies: 1, delta: -1) }
      assert_raises(ArgumentError) { Decks::OwnedCopiesSetter.call(deck: @deck, card: @card, delta: "-1") }
      assert_equal 3, @deck_card.reload.owned_copies
    end

    test "rejects a non-physical deck" do
      live = @user.decks.create!(name: "Live", physical: false, standard_pool: standard_pools(:twm_por))
      live.deck_cards.create!(card: @card, quantity: 2)

      assert_raises(Decks::OwnedCopiesSetter::NotPhysicalError) do
        Decks::OwnedCopiesSetter.call(deck: live, card: @card, owned_copies: 1)
      end
    end
  end
end
