require "test_helper"

class DeckTest < ActiveSupport::TestCase
  test "has_many deck_results" do
    deck = decks(:one)
    assert_respond_to deck, :deck_results
  end

  test "belongs to an optional archetype" do
    deck = decks(:one)

    assert deck.valid?
    assert_nil deck.archetype

    deck.archetype = archetypes(:ogerpon)
    assert deck.valid?
    assert_equal archetypes(:ogerpon), deck.reload.archetype if deck.save
  end

  test "nullifies the deck archetype when the archetype is destroyed" do
    deck = decks(:one)
    deck.update!(archetype: archetypes(:ogerpon))

    archetypes(:ogerpon).destroy

    assert_nil deck.reload.archetype
  end

  test "destroying deck destroys deck_results" do
    deck = decks(:one)

    assert_difference "DeckResult.count", -deck.deck_results.count do
      deck.destroy
    end
  end

  test "defaults to the standard format and no support flags" do
    deck = Deck.new(user: users(:one), name: "Fresh")

    assert deck.standard?
    assert_not deck.physical?
    assert_not deck.tcg_live?
    assert_not deck.has_proxies?
  end

  test "rejects an unknown format" do
    deck = Deck.new(user: users(:one), name: "Bad", format: "vintage")

    assert_not deck.valid?
    assert_includes deck.errors[:format], "is not included in the list"
  end

  test "requires a format name when format is other" do
    deck = Deck.new(user: users(:one), name: "Other", format: "other")

    assert_not deck.valid?
    assert_includes deck.errors[:other_format_name], "can't be blank"

    deck.other_format_name = "Pocket"
    assert deck.valid?
  end

  test "clears the format name when leaving the other format" do
    deck = Deck.create!(user: users(:one), name: "Other", format: "other", other_format_name: "Pocket")

    deck.update!(format: "standard")

    assert_nil deck.other_format_name
  end

  test "clears proxies when the deck is not physical" do
    deck = Deck.create!(user: users(:one), name: "Live", physical: true, has_proxies: true)

    deck.update!(physical: false)

    assert_not deck.has_proxies?
  end

  test "format_label uses the custom name for the other format" do
    deck = Deck.new(user: users(:one), name: "Other", format: "other", other_format_name: "Pocket")

    assert_equal "Pocket", deck.format_label
  end

  test "format_label humanizes the known formats" do
    deck = Deck.new(user: users(:one), name: "Std", format: "expanded")

    assert_equal "Expanded", deck.format_label
  end

  test "flipping physical to false releases owned copies" do
    deck = users(:one).decks.create!(name: "Phys", physical: true)
    deck.deck_cards.create!(card: cards(:honedge), quantity: 2, owned_copies: 2)

    deck.update!(physical: false)

    assert_equal 0, deck.deck_cards.sum(:owned_copies)
  end
end
