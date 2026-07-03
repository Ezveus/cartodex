require "test_helper"

class DeckCardTest < ActiveSupport::TestCase
  test "owned_copies defaults to 0" do
    deck = decks(:one)
    dc = deck.deck_cards.create!(card: cards(:trainer_card), quantity: 2)
    assert_equal 0, dc.owned_copies
  end

  test "owned_copies cannot exceed quantity" do
    deck = users(:one).decks.create!(name: "Phys", physical: true)
    dc = deck.deck_cards.new(card: cards(:honedge), quantity: 2, owned_copies: 3)
    assert_not dc.valid?
    assert_includes dc.errors[:owned_copies], "cannot exceed quantity"
  end

  test "owned_copies must be 0 on a non-physical deck" do
    deck = decks(:one) # not physical
    dc = deck.deck_cards.new(card: cards(:honedge), quantity: 2, owned_copies: 1)
    assert_not dc.valid?
    assert_includes dc.errors[:owned_copies], "must be 0 for a non-physical deck"
  end

  test "owned_copies is allowed on a physical deck" do
    deck = users(:one).decks.create!(name: "Phys", physical: true)
    dc = deck.deck_cards.new(card: cards(:honedge), quantity: 2, owned_copies: 2)
    assert dc.valid?
  end
end
