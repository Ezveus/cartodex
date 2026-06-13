require "test_helper"

class Decks::ArchetypeDetectorTest < ActiveSupport::TestCase
  setup do
    @deck = decks(:one)
    @deck.deck_cards.destroy_all
  end

  test "returns a blank result for a deck with no Pokémon" do
    @deck.deck_cards.create!(card: cards(:trainer_card), quantity: 4)

    result = Decks::ArchetypeDetector.call(@deck.reload)

    assert_not result.matched?
    assert_nil result.primary
  end

  test "matches an existing single-Pokémon archetype by name" do
    @deck.deck_cards.create!(card: cards(:teal_mask_ogerpon_ex), quantity: 2)
    @deck.deck_cards.create!(card: cards(:trainer_card), quantity: 4)

    result = Decks::ArchetypeDetector.call(@deck.reload)

    assert result.matched?
    assert_equal archetypes(:ogerpon), result.archetype
  end

  test "prefers a two-Pokémon archetype over a single-Pokémon one" do
    @deck.deck_cards.create!(card: cards(:budew_pre), quantity: 1)
    @deck.deck_cards.create!(card: cards(:teal_mask_ogerpon_ex), quantity: 2)

    result = Decks::ArchetypeDetector.call(@deck.reload)

    assert_equal archetypes(:budew_ogerpon), result.archetype
  end

  test "does not match a two-Pokémon archetype whose secondary is missing" do
    @deck.deck_cards.create!(card: cards(:budew_pre), quantity: 1)

    result = Decks::ArchetypeDetector.call(@deck.reload)

    assert_not result.matched?
    assert_equal cards(:budew_pre), result.primary
  end

  test "suggests the deck's own Pokémon when no archetype matches" do
    @deck.deck_cards.create!(card: cards(:doublade), quantity: 1)

    result = Decks::ArchetypeDetector.call(@deck.reload)

    assert_not result.matched?
    assert_equal cards(:doublade), result.primary
  end
end
