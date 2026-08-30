require "test_helper"

class Decks::ArchetypeDetectorTest < ActiveSupport::TestCase
  setup do
    @deck = decks(:one)
    @deck.deck_cards.destroy_all
  end

  # --- Suggestion (Pokémon only, unchanged) ---

  test "returns a blank result for a deck holding nothing an archetype names" do
    @deck.deck_cards.create!(card: cards(:trainer_card), quantity: 4)

    result = Decks::ArchetypeDetector.call(@deck.reload)

    assert_not result.matched?
    assert_nil result.suggested_primary
  end

  test "suggests the deck's own Pokémon when no archetype matches" do
    @deck.deck_cards.create!(card: cards(:doublade), quantity: 1)

    result = Decks::ArchetypeDetector.call(@deck.reload)

    assert_not result.matched?
    assert_equal cards(:doublade), result.suggested_primary
  end

  # Ranking Trainers by copy count would propose Iono and Ultra Ball on every deck
  # ever imported, so suggestion stays Pokémon-only even though matching no longer is.
  test "never suggests a Trainer, however many copies the deck plays" do
    @deck.deck_cards.create!(card: cards(:bosss_orders_meg), quantity: 4)
    @deck.deck_cards.create!(card: cards(:doublade), quantity: 1)

    result = Decks::ArchetypeDetector.call(@deck.reload)

    assert_equal cards(:doublade), result.suggested_primary
    assert_nil result.suggested_secondary
  end

  # --- Matching (any card type, keyed on fingerprints) ---

  test "matches an existing single-member archetype" do
    @deck.deck_cards.create!(card: cards(:teal_mask_ogerpon_ex), quantity: 2)
    @deck.deck_cards.create!(card: cards(:trainer_card), quantity: 4)

    result = Decks::ArchetypeDetector.call(@deck.reload)

    assert result.matched?
    assert_equal archetypes(:ogerpon), result.archetype
  end

  # The printing an archetype names is a display reference: identity is the
  # fingerprint, so a deck playing another printing of the same card still matches.
  test "matches a deck holding a different printing of the archetype's card" do
    reprint = cards(:froakie_cri)
    reprint.update_column(:fingerprint, "ogerpon_shared")
    @deck.deck_cards.create!(card: reprint, quantity: 2)

    result = Decks::ArchetypeDetector.call(@deck.reload)

    assert_equal archetypes(:ogerpon), result.archetype
  end

  test "matches a Trainer-led archetype" do
    trainer_archetype = Archetype.create!(primary_card: cards(:bosss_orders_meg), name: "Boss Box")
    @deck.deck_cards.create!(card: cards(:bosss_orders_meg), quantity: 4)

    result = Decks::ArchetypeDetector.call(@deck.reload)

    assert_equal trainer_archetype, result.archetype
  end

  test "prefers a two-member archetype over a single-member one" do
    @deck.deck_cards.create!(card: cards(:budew_pre), quantity: 1)
    @deck.deck_cards.create!(card: cards(:teal_mask_ogerpon_ex), quantity: 2)

    result = Decks::ArchetypeDetector.call(@deck.reload)

    assert_equal archetypes(:budew_ogerpon), result.archetype
  end

  # A Trainer identifies a deck far less than a Pokémon does, so an archetype
  # named after one can only win when nothing better matches at all.
  test "a Pokémon archetype outranks a Trainer one on the same deck" do
    Archetype.create!(primary_card: cards(:bosss_orders_meg), name: "Boss Box")
    @deck.deck_cards.create!(card: cards(:bosss_orders_meg), quantity: 4)
    @deck.deck_cards.create!(card: cards(:teal_mask_ogerpon_ex), quantity: 2)

    result = Decks::ArchetypeDetector.call(@deck.reload)

    assert_equal archetypes(:ogerpon), result.archetype
  end

  test "does not match a two-member archetype whose secondary is missing" do
    @deck.deck_cards.create!(card: cards(:budew_pre), quantity: 1)

    result = Decks::ArchetypeDetector.call(@deck.reload)

    assert_not result.matched?
    assert_equal cards(:budew_pre), result.suggested_primary
  end
end
