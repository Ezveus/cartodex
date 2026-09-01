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

    test "physical deck backs reals greedily then fills proxies" do
      user = users(:one)
      card = cards(:honedge)
      user.collections.find_or_create_by!(card: card).update!(quantity: 3)
      deck = user.decks.create!(name: "A", physical: true, standard_pool: standard_pools(:twm_por))

      deck_card = Decks::CardAdder.call(deck: deck, card: card, quantity: 4)

      assert_equal 4, deck_card.quantity
      assert_equal 3, deck_card.owned_copies # 3 reals + 1 proxy
    end

    test "a second physical deck gets only proxies once owned copies are exhausted" do
      user = users(:one)
      card = cards(:honedge)
      user.collections.find_or_create_by!(card: card).update!(quantity: 3)
      deck_a = user.decks.create!(name: "A", physical: true, standard_pool: standard_pools(:twm_por))
      deck_b = user.decks.create!(name: "B", physical: true, standard_pool: standard_pools(:twm_por))
      Decks::CardAdder.call(deck: deck_a, card: card, quantity: 4) # takes all 3 reals

      deck_card_b = Decks::CardAdder.call(deck: deck_b, card: card, quantity: 4)

      assert_equal 4, deck_card_b.quantity
      assert_equal 0, deck_card_b.owned_copies # all proxies
    end

    test "non-physical deck never backs reals" do
      user = users(:one)
      card = cards(:honedge)
      user.collections.find_or_create_by!(card: card).update!(quantity: 3)
      deck = user.decks.create!(name: "Live", physical: false, standard_pool: standard_pools(:twm_por))

      deck_card = Decks::CardAdder.call(deck: deck, card: card, quantity: 2)

      assert_equal 0, deck_card.owned_copies
    end
  end
end
