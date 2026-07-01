require "test_helper"

module Decks
  class CardTransferTest < ActiveSupport::TestCase
    # Fixtures: collection(:one) = user one / honedge / qty 1
    #           deck_card(:one)  = deck one (user one) / honedge / qty 1
    setup do
      @user = users(:one)
      @deck = decks(:one)
      @card = cards(:honedge)
    end

    test "direction :in moves a card from collection to deck" do
      result = Decks::CardTransfer.call(user: @user, deck: @deck, card: @card, direction: :in, quantity: 1)

      assert_equal 0, result.collection_quantity
      assert_equal 2, result.deck_quantity
      assert_equal 0, @user.collections.find_by(card: @card).quantity
      assert_equal 2, @deck.deck_cards.find_by(card: @card).quantity
    end

    test "direction :in floors the collection at zero without enforcement" do
      result = Decks::CardTransfer.call(user: @user, deck: @deck, card: @card, direction: :in, quantity: 5)

      assert_equal 0, result.collection_quantity
      assert_equal 6, result.deck_quantity
    end

    test "direction :out returns cards to collection and destroys an emptied deck_card" do
      result = Decks::CardTransfer.call(user: @user, deck: @deck, card: @card, direction: :out, quantity: 1)

      assert_equal 2, result.collection_quantity
      assert_equal 0, result.deck_quantity
      assert_nil @deck.deck_cards.find_by(card: @card)
    end

    test "direction :out over-withdraw destroys the deck_card and still credits the full quantity" do
      result = Decks::CardTransfer.call(user: @user, deck: @deck, card: @card, direction: :out, quantity: 3)

      assert_equal 4, result.collection_quantity # started at 1, +3
      assert_equal 0, result.deck_quantity
      assert_nil @deck.deck_cards.find_by(card: @card)
    end

    test "raises on an unknown direction" do
      assert_raises(ArgumentError) do
        Decks::CardTransfer.call(user: @user, deck: @deck, card: @card, direction: :sideways)
      end
    end
  end
end
