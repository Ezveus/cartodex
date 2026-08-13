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

  # The stored name carries an uppercase accented letter on purpose: SQLite's LIKE folds F/f but
  # not É/é, so a lowercase query can only match through name_normalized. Were the scope to
  # compare `name` again, this test would go red — that's the regression it exists to catch.
  test "name_matching ignores case on accented letters" do
    deck = decks(:one)
    deck.update!(name: "FLABÉBÉ Toolbox")

    %w[FLABÉBÉ Flabébé flabébé BÉBÉ bébé].each do |query|
      assert_includes Deck.name_matching(query), deck, "#{query.inspect} must match"
    end
  end

  test "name_matching treats LIKE metacharacters in the query as literals" do
    deck = decks(:one)
    deck.update!(name: "Ogerpon Toolbox")

    assert_includes Deck.name_matching("ogerpon"), deck, "sanity: the plain spelling matches"
    assert_empty Deck.name_matching("og_rpon"), "_ must not act as a wildcard"
    assert_empty Deck.name_matching("oger%on"), "% must not act as a wildcard"
  end

  # Fixtures are inserted without callbacks, so decks.yml spells name_normalized out by hand;
  # this is what stops the two from drifting when a fixture name is edited.
  test "every deck fixture carries the normalization its name implies" do
    Deck.find_each do |deck|
      assert_equal deck.name.downcase, deck.name_normalized, "#{deck.name.inspect} fixture is out of step"
    end
  end

  test "search matches the deck's own name" do
    deck = decks(:one)
    deck.update!(name: "Ogerpon Toolbox")

    assert_includes Deck.search("ogerpon"), deck
  end

  # A deck tagged "Teal Mask Ogerpon ex" must surface for "Ogerpon" even when its own name says
  # nothing about it — that's the whole point of composing Archetype.search in.
  test "search matches through the deck's archetype" do
    deck = decks(:one)
    deck.update!(name: "Tuesday List", archetype: archetypes(:ogerpon))

    assert_includes Deck.search("ogerpon"), deck
  end

  test "search matches through the archetype's member Pokémon" do
    deck = decks(:one)
    deck.update!(name: "Tuesday List", archetype: archetypes(:budew_ogerpon))

    assert_includes Deck.search("budew"), deck
  end

  # The archetype side is a subquery, not a join, so a deck matching on both sides is still one row.
  test "search returns each deck once when name and archetype both match" do
    deck = decks(:one)
    deck.update!(name: "Ogerpon Toolbox", archetype: archetypes(:ogerpon))

    assert_equal [ deck.id ], Deck.search("ogerpon").pluck(:id)
  end

  test "search treats LIKE metacharacters in the query as literals" do
    decks(:one).update!(name: "Ogerpon Toolbox", archetype: archetypes(:ogerpon))

    assert_empty Deck.search("og_rpon"), "_ must not act as a wildcard"
    assert_empty Deck.search("oger%on"), "% must not act as a wildcard"
  end

  test "search chains off a user's decks" do
    decks(:one).update!(name: "Ogerpon Toolbox", user: users(:one))
    decks(:two).update!(name: "Ogerpon Toolbox", user: users(:two))

    results = users(:one).decks.search("ogerpon")

    assert_includes results, decks(:one)
    assert_not_includes results, decks(:two)
  end
end
