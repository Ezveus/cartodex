require "test_helper"

class Decks::ArchetypeDetectorTest < ActiveSupport::TestCase
  setup do
    @deck = decks(:one)
    @deck.deck_cards.destroy_all
  end

  # --- Suggestion (Pokémon only, unchanged) ---

  # cards(:trainer_card) has a NULL fingerprint (a Task 2 fixture, deliberately),
  # so deck_fingerprints comes back empty and match_existing short-circuits
  # before any query runs. This is a different branch from the query actually
  # running and finding nothing — see the next test for that.
  test "returns a blank result when the deck carries no fingerprint at all" do
    @deck.deck_cards.create!(card: cards(:trainer_card), quantity: 4)

    result = Decks::ArchetypeDetector.call(@deck.reload)

    assert_not result.matched?
    assert_nil result.suggested_primary
  end

  # cards(:bosss_orders_meg) carries a real fingerprint (bosss_orders_meg_fp) that
  # no fixture archetype names, so this exercises match_existing's query actually
  # running and returning nothing — not the empty-fingerprints short-circuit above.
  test "returns a blank result for a deck holding nothing an archetype names" do
    @deck.deck_cards.create!(card: cards(:bosss_orders_meg), quantity: 4)

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

  # The denormalised archetypes.primary_fingerprint column backs the unique index
  # and nothing else: matching joins cards and reads the live value. Here the card
  # moves and the copy stays stale, so an implementation reading the copy finds
  # nothing while the correct one still matches.
  test "matches on the card's live fingerprint, not the archetype's denormalised copy" do
    cards(:teal_mask_ogerpon_ex).update_column(:fingerprint, "ogerpon_v2")
    assert_equal "ogerpon_shared", archetypes(:ogerpon).primary_fingerprint,
      "the copy must still be stale for this test to mean anything"
    @deck.deck_cards.create!(card: cards(:teal_mask_ogerpon_ex), quantity: 2)

    result = Decks::ArchetypeDetector.call(@deck.reload)

    assert_equal archetypes(:ogerpon), result.archetype
  end

  # 3-vs-3: a lone rule-box Pokémon against a Pokémon + Trainer pair. Score alone
  # cannot separate them, so this is the only test where member_count decides.
  #
  # The fixture archetypes(:budew_ogerpon) is destroyed first: once both budew_pre
  # and the now-rule-box teal_mask_ogerpon_ex are in the deck below, it would also
  # qualify, and at a higher score (2 + 3 = 5) than the 3-vs-3 tie this test means
  # to exercise, masking it.
  test "breaks a score tie in favour of the archetype with more members" do
    archetypes(:budew_ogerpon).destroy
    cards(:teal_mask_ogerpon_ex).update!(pokemon_subtype: pokemon_subtypes(:pokemon_ex))
    pair = Archetype.create!(primary_card: cards(:budew_pre), secondary_card: cards(:bosss_orders_meg),
      name: "Budew Boss")
    @deck.deck_cards.create!(card: cards(:teal_mask_ogerpon_ex), quantity: 2)
    @deck.deck_cards.create!(card: cards(:budew_pre), quantity: 1)
    @deck.deck_cards.create!(card: cards(:bosss_orders_meg), quantity: 4)

    result = Decks::ArchetypeDetector.call(@deck.reload)

    assert_equal pair, result.archetype
  end
end
