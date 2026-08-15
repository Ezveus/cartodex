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

  test "is unique per deck and card" do
    deck = decks(:one)
    card = cards(:trainer_card)
    deck.deck_cards.create!(card: card, quantity: 1)
    dup = deck.deck_cards.build(card: card, quantity: 1)
    assert_not dup.valid?
    assert_includes dup.errors[:card_id], "has already been taken"
  end

  test "proxies is quantity minus owned_copies" do
    deck = users(:one).decks.create!(name: "Phys", physical: true)
    dc = deck.deck_cards.create!(card: cards(:honedge), quantity: 3, owned_copies: 1)
    assert_equal 2, dc.proxies
  end

  test "proxies is zero when fully backed" do
    deck = users(:one).decks.create!(name: "Phys", physical: true)
    dc = deck.deck_cards.create!(card: cards(:honedge), quantity: 2, owned_copies: 2)
    assert_equal 0, dc.proxies
  end

  test "with_proxies selects the rows carrying at least one proxy" do
    deck = users(:one).decks.create!(name: "Phys", physical: true)
    proxied = deck.deck_cards.create!(card: cards(:honedge), quantity: 3, owned_copies: 1)
    backed = deck.deck_cards.create!(card: cards(:doublade), quantity: 2, owned_copies: 2)

    assert_includes DeckCard.with_proxies, proxied
    assert_not_includes DeckCard.with_proxies, backed
  end
end
