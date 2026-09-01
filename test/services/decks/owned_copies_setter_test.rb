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

    test "rejects a non-physical deck" do
      live = @user.decks.create!(name: "Live", physical: false, standard_pool: standard_pools(:twm_por))
      live.deck_cards.create!(card: @card, quantity: 2)

      assert_raises(Decks::OwnedCopiesSetter::NotPhysicalError) do
        Decks::OwnedCopiesSetter.call(deck: live, card: @card, owned_copies: 1)
      end
    end
  end
end
