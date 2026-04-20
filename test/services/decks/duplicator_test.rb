require "test_helper"

class Decks::DuplicatorTest < ActiveSupport::TestCase
  setup do
    @deck = decks(:one)
    @deck.update!(name: "Original", description: "A fine deck")
    @deck.deck_cards.destroy_all
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 2)
    @deck.deck_cards.create!(card: cards(:trainer_card), quantity: 3)
  end

  test "creates a new deck owned by the same user" do
    new_deck = Decks::Duplicator.call(@deck)

    assert_not_equal @deck.id, new_deck.id
    assert_equal @deck.user, new_deck.user
  end

  test "prefixes the name with 'Copy of '" do
    new_deck = Decks::Duplicator.call(@deck)

    assert_equal "Copy of Original", new_deck.name
  end

  test "copies the description" do
    new_deck = Decks::Duplicator.call(@deck)

    assert_equal "A fine deck", new_deck.description
  end

  test "copies deck_cards with their quantities" do
    new_deck = Decks::Duplicator.call(@deck)

    pairs = new_deck.deck_cards.map { |dc| [ dc.card_id, dc.quantity ] }.sort
    expected = @deck.deck_cards.map { |dc| [ dc.card_id, dc.quantity ] }.sort

    assert_equal expected, pairs
  end

  test "duplicates a deck with no cards" do
    @deck.deck_cards.destroy_all

    new_deck = Decks::Duplicator.call(@deck)

    assert_equal 0, new_deck.deck_cards.count
  end
end
