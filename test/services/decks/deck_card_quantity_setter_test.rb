require "test_helper"

module Decks
  class DeckCardQuantitySetterTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      @card = cards(:honedge)
      @user.collections.find_or_create_by!(card: @card).update!(quantity: 3)
      @deck = @user.decks.create!(name: "A", physical: true, standard_pool: standard_pools(:twm_por))
      @deck.deck_cards.create!(card: @card, quantity: 4, owned_copies: 3)
    end

    test "reducing quantity below owned_copies recaps the reals" do
      dc = Decks::DeckCardQuantitySetter.call(deck: @deck, card: @card, quantity: 2)
      assert_equal 2, dc.quantity
      assert_equal 2, dc.owned_copies
    end

    test "setting quantity to 0 removes the deck_card" do
      result = Decks::DeckCardQuantitySetter.call(deck: @deck, card: @card, quantity: 0)
      assert_nil result
      assert_nil @deck.deck_cards.find_by(card: @card)
    end

    test "does not auto-bump reals when increasing quantity" do
      dc = Decks::DeckCardQuantitySetter.call(deck: @deck, card: @card, quantity: 6)
      assert_equal 6, dc.quantity
      assert_equal 3, dc.owned_copies # unchanged, no greedy backing
    end

    test "rejects non-integer quantity without destroying the deck_card" do
      assert_raises(ArgumentError) do
        Decks::DeckCardQuantitySetter.call(deck: @deck, card: @card, quantity: "abc")
      end
      assert_equal 4, @deck.deck_cards.find_by(card: @card).quantity # unchanged, not destroyed
    end
  end
end
