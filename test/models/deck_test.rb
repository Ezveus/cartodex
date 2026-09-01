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

    deck.update!(format: "standard", standard_pool: standard_pools(:twm_por))

    assert_nil deck.other_format_name
  end

  test "has_proxies? is false when every card on a physical deck is fully backed" do
    deck = users(:one).decks.create!(name: "Phys", physical: true, standard_pool: standard_pools(:twm_por))
    deck.deck_cards.create!(card: cards(:honedge), quantity: 2, owned_copies: 2)

    assert_not deck.has_proxies?
  end

  test "has_proxies? is true when a card on a physical deck is not fully backed" do
    deck = users(:one).decks.create!(name: "Phys", physical: true, standard_pool: standard_pools(:twm_por))
    deck.deck_cards.create!(card: cards(:honedge), quantity: 2, owned_copies: 1)

    assert deck.has_proxies?
  end

  test "has_proxies? is false for an empty physical deck" do
    deck = users(:one).decks.create!(name: "Phys", physical: true, standard_pool: standard_pools(:twm_por))

    assert_not deck.has_proxies?
  end

  # A non-physical deck never consumes the collection, so its cards sit at owned_copies 0 by
  # construction. That is not the same thing as playing proxies, and must not raise the badge.
  test "has_proxies? is false for a non-physical deck holding cards" do
    deck = users(:one).decks.create!(name: "Live", tcg_live: true, standard_pool: standard_pools(:twm_por))
    deck.deck_cards.create!(card: cards(:honedge), quantity: 2)

    assert_not deck.has_proxies?
  end

  test "has_proxies? drops when the deck stops being physical" do
    deck = users(:one).decks.create!(name: "Phys", physical: true, standard_pool: standard_pools(:twm_por))
    deck.deck_cards.create!(card: cards(:honedge), quantity: 2, owned_copies: 1)
    assert deck.has_proxies?, "sanity: the deck starts out holding a proxy"

    deck.update!(physical: false)

    assert_not deck.has_proxies?
  end

  test "with_proxies selects physical decks holding an unbacked card" do
    proxied = users(:one).decks.create!(name: "Proxied", physical: true, standard_pool: standard_pools(:twm_por))
    proxied.deck_cards.create!(card: cards(:honedge), quantity: 2, owned_copies: 1)
    backed = users(:one).decks.create!(name: "Backed", physical: true, standard_pool: standard_pools(:twm_por))
    backed.deck_cards.create!(card: cards(:doublade), quantity: 1, owned_copies: 1)

    assert_includes Deck.with_proxies, proxied
    assert_not_includes Deck.with_proxies, backed
    assert_includes Deck.without_proxies, backed
    assert_not_includes Deck.without_proxies, proxied
  end

  # The same rows that has_proxies? clears in Ruby, the scope must clear in SQL: a non-physical
  # deck's cards are all at owned_copies 0, which the bare `owned_copies < quantity` test matches.
  test "with_proxies ignores non-physical decks" do
    live = users(:one).decks.create!(name: "Live", tcg_live: true, standard_pool: standard_pools(:twm_por))
    live.deck_cards.create!(card: cards(:honedge), quantity: 2)

    assert_not_includes Deck.with_proxies, live
    assert_includes Deck.without_proxies, live
  end

  test "without_proxies covers a physical deck with no cards at all" do
    empty = users(:one).decks.create!(name: "Empty", physical: true, standard_pool: standard_pools(:twm_por))

    assert_includes Deck.without_proxies, empty
    assert_not_includes Deck.with_proxies, empty
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
    deck = users(:one).decks.create!(name: "Phys", physical: true, standard_pool: standard_pools(:twm_por))
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

  # LIKE '%…%' can't use an index, so the pattern's length is a multiplier on a full scan the
  # spotlight runs per keystroke. Nothing legitimate reaches the cap; an abusive query does.
  test "name_matching caps how long a LIKE pattern a request can ask for" do
    pattern = Deck.name_matching("a" * 500).to_sql[/'%(a+)%'/, 1]

    assert_equal NameNormalizable::MAX_QUERY_LENGTH, pattern.length
  end

  test "name_matching leaves a query under the cap alone" do
    deck = decks(:one)
    deck.update!(name: "Ogerpon Toolbox")

    assert_includes Deck.name_matching("ogerpon toolbox"), deck
  end

  test "search chains off a user's decks" do
    decks(:one).update!(name: "Ogerpon Toolbox", user: users(:one))
    decks(:two).update!(name: "Ogerpon Toolbox", user: users(:two))

    results = users(:one).decks.search("ogerpon")

    assert_includes results, decks(:one)
    assert_not_includes results, decks(:two)
  end

  test "requires a standard pool when the format is standard" do
    deck = Deck.new(user: users(:one), name: "Anchorless", format: "standard")

    assert_not deck.valid?
    assert_includes deck.errors[:standard_pool], "can't be blank"
  end

  # Only Standard rotates. An anchor left behind by a format change would claim a
  # card pool that the new format does not have.
  test "clears the standard pool when the format is not standard" do
    deck = Deck.create!(
      user: users(:one), name: "Was standard", format: "standard",
      standard_pool: standard_pools(:twm_por)
    )

    deck.update!(format: "glc")

    assert_nil deck.reload.standard_pool_id
  end

  test "accepts a standard pool being absent on an eternal format" do
    deck = Deck.new(user: users(:one), name: "Singleton", format: "glc")

    assert deck.valid?
  end

  test "format_label names the standard pool the deck is anchored to" do
    deck = Deck.new(user: users(:one), name: "Anchored", format: "standard",
      standard_pool: standard_pools(:twm_por))

    assert_equal "Standard (TWM-POR)", deck.format_label
  end

  # Pre-backfill rows and any row the anchor does not apply to.
  test "format_label falls back to the bare format name without a pool" do
    deck = Deck.new(user: users(:one), name: "Anchorless", format: "standard")

    assert_equal "Standard", deck.format_label
  end
end
