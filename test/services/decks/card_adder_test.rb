require "test_helper"

module Decks
  class CardAdderTest < ActiveSupport::TestCase
    test "creates a deck_card when none exists" do
      deck = decks(:two)
      card = cards(:honedge) # deck(:two) holds doublade, not honedge

      deck_card = Decks::CardAdder.call(deck: deck, card: card, quantity: 2)

      assert_equal 2, deck_card.quantity
      assert_equal deck, deck_card.deck
      assert_equal card, deck_card.card
    end

    test "increments an existing deck_card" do
      deck = decks(:one) # fixture: deck_card(:one) is honedge, quantity 1
      card = cards(:honedge)

      deck_card = Decks::CardAdder.call(deck: deck, card: card, quantity: 2)

      assert_equal 3, deck_card.quantity
    end
  end
end
