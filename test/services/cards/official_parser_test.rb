require "test_helper"

# Every fixture here is a verbatim `section.card-detail` fragment captured from
# www.pokemon.com — the same bytes `bin/scrape_official_cards` writes. `30th_1` was captured
# without a browser and so carries none of the `data-gtm-vis-*` attributes the other sixteen do;
# it is kept for exactly that reason.
class Cards::OfficialParserTest < ActiveSupport::TestCase
  FIXTURE_DIR = Rails.root.join("test/fixtures/files/official_cards")

  def parse(name)
    Cards::OfficialParser.call(file_fixture("official_cards/#{name}.html").read)
  end

  # --- identity -----------------------------------------------------------------------------

  test "keeps the lowercase ex suffix, which names a different card from EX" do
    assert_equal "Greninja ex", parse("30th_21")[:name]
  end

  test "reads a name from the fragment the server rendered, without the browser's attributes" do
    assert_equal "Exeggcute", parse("30th_1")[:name]
  end

  test "set number is the numerator, so a secret rare keeps its own number" do
    assert_equal "129", parse("30th_129")[:set_number]
    assert_equal "1", parse("30th-c_1")[:set_number]
  end

  # --- stage --------------------------------------------------------------------------------

  test "stage comes from the type line on a plain Pokémon" do
    assert_equal "Basic", parse("30th_130")[:stage]
    assert_equal "Stage 1", parse("30th_129")[:stage]
    assert_equal "Stage 2", parse("30th-c_1")[:stage]
  end

  test "an ex with no evolution is Basic, which the type line never says" do
    # The type line reads "Pokémon ex" in place of a stage. Decks::Odds::Groups counts a Basic as
    # `card_type == "Pokémon" && stage == "Basic"`, so getting this wrong moves the mulligan rate
    # in the reassuring direction on exactly the decks that play these cards.
    assert_equal "Basic", parse("30th_15")[:stage]
    assert_equal "Basic", parse("30th_53")[:stage]
  end

  test "an ex that evolves has no stage, because the source does not say which" do
    greninja = parse("30th_21")

    assert_nil greninja[:stage]
    assert_equal "Frogadier", greninja[:evolves_from]
  end

  # --- energy -------------------------------------------------------------------------------

  test "the type symbol is read off the card's own type icon" do
    # Deliberately *not* named for the class-over-tooltip rule any more: on this node the two
    # agree, so the assertion passes either way and proved nothing about the distinction.
    # What holds that rule is the weakness/resistance pair below — those icons carry no `title`
    # at all, so a parser reading the tooltip returns nil for them.
    assert_equal "Darkness", parse("30th_100")[:type_symbol]
    assert_equal "Dragon", parse("30th_110")[:type_symbol]
  end

  test "SYMBOL_BY_TYPE is exactly the inverse of the alphabet Cards::Fetcher reads" do
    assert_equal Cards::Fetcher::ENERGY_SYMBOLS.invert, Cards::OfficialParser::SYMBOL_BY_TYPE
  end

  test "ENERGY_BY_SLUG maps each slug to its own energy, not merely to some valid one" do
    # Asserting the value *set* is what let a Fairy/Psychic swap survive: both are members of
    # Card::ENERGY_TYPES, so the inclusion validation cannot see it and no card in this set plays
    # either type. Pinning the pairs is what makes the swap unrepresentable.
    assert_equal(
      { "grass" => "Grass", "fire" => "Fire", "water" => "Water", "lightning" => "Lightning",
        "fighting" => "Fighting", "psychic" => "Psychic", "darkness" => "Darkness",
        "metal" => "Metal", "fairy" => "Fairy", "dragon" => "Dragon", "colorless" => "Colorless" },
      Cards::OfficialParser::ENERGY_BY_SLUG
    )
  end

  test "every energy icon appearing in the fixtures is a slug the parser knows" do
    slugs = Dir[Rails.root.join("test/fixtures/files/official_cards/*.html")]
      .flat_map { |f| File.read(f).scan(/icon-([a-z]+)"/).flatten }
      .uniq
    known = Cards::OfficialParser::ENERGY_BY_SLUG.keys + [ Cards::OfficialParser::FREE_SLUG ]

    assert_empty slugs - known, "unmapped energy icon class(es)"
  end

  # --- attacks ------------------------------------------------------------------------------

  test "attack cost is re-encoded into the Limitless alphabet" do
    assert_equal %w[W WW], parse("30th_21")[:attacks].map { _1[:cost] }
    assert_equal %w[C LLC], parse("30th_53")[:attacks].map { _1[:cost] }
  end

  test "a free attack costs \"0\", the way Limitless writes it" do
    # 26 attacks in the catalogue carry "0" and none carries "". The cost feeds
    # compute_fingerprint, so an empty string gives the card a fingerprint no other printing
    # of it shares.
    assert_equal [ "0" ], parse("30th_120")[:attacks].map { _1[:cost] }
  end

  test "damage belongs to the attack that prints it, not to the first one" do
    assert_equal [ nil, "160" ], parse("30th_21")[:attacks].map { _1[:damage] }
    assert_equal [ nil, "200" ], parse("30th_53")[:attacks].map { _1[:damage] }
    assert_equal [ "30+", "90" ], parse("30th_5")[:attacks].map { _1[:damage] }
  end

  test "damage keeps the multiplier and the plus verbatim" do
    assert_equal [ "30×" ], parse("30th_120")[:attacks].map { _1[:damage] }
    assert_equal [ "100+" ], parse("30th_92")[:attacks].map { _1[:damage] }
  end

  test "an empty effect block is nil, not an empty string" do
    assert_nil parse("30th_21")[:attacks].second[:effect]
    assert_equal "Discard all Energy from this Pokémon.", parse("30th_53")[:attacks].second[:effect]
  end

  # --- punctuation --------------------------------------------------------------------------

  test "the typographic apostrophe is folded, because the catalogue is written with the plain one" do
    # Measured: 421 card names in the catalogue carry U+0027 and none carries U+2019, and 1626
    # attack effects say "opponent's" against 9 that do not. The source uses U+2019 throughout —
    # it is the only character above U+2000 in all 17 fixtures.
    effect = parse("30th_1")[:attacks].first[:effect]

    assert_equal "Your opponent's Active Pokémon is now Asleep.", effect
    assert_not_includes effect, "’"
  end

  test "folding it is what keeps these cards inside the role vocabulary" do
    # CardLabels::RoleSuggester's gust and disruption rules spell "opponent's" with the plain
    # apostrophe, so unfolded text silently matches neither — and `/cards?role=gust` would print a
    # list these cards are missing from, while the odds page counted them as roleless.
    volbeat = parse("30th_3")[:attacks].find { _1[:name] == "Luring Glow" }

    assert_match CardLabels::RoleSuggester::RULES["gust"], volbeat[:effect]
  end

  test "the multiplication sign is left alone, being the catalogue's own spelling" do
    # 395 attacks already carry U+00D7 in `damage`; folding it to "x" would be the same mistake
    # in the other direction.
    assert_equal "30×", parse("30th_120")[:attacks].first[:damage]
  end

  # --- abilities ----------------------------------------------------------------------------

  test "an ability keeps its name and not the era label the page prints in front of it" do
    # The Classic Collection reprints a Base Set card, and the page renders its rule box as
    # "[Pokémon Power] Energy Burn". No ability in the catalogue carries a bracket — Limitless
    # prefixes "Ability:" and Cards::Fetcher strips it, which is the same normalisation.
    # It matters twice: ability names enter compute_fingerprint, and Decks::CardmarketExporter
    # joins them into the wishlist line, where the brackets resolve to nothing.
    assert_equal [ "Energy Burn" ], parse("30th-c_1")[:abilities].map { _1[:name] }
  end

  test "the Pokémon ex rule is neither an attack nor an ability" do
    # It shares the .ability div with both. 30th_53 renders three of them and exactly two are
    # attacks; storing the third would put rules text on every ex card in the set and move
    # their fingerprints.
    pikachu = parse("30th_53")

    assert_equal 2, pikachu[:attacks].size
    assert_empty pikachu[:abilities]
  end

  test "a real ability is read, beside the attack and the rule box on the same card" do
    mew = parse("30th_66")

    assert_equal [ "Memory Helix" ], mew[:abilities].map { _1[:name] }
    assert_match "use the attacks of any of your Benched", mew[:abilities].first[:effect]
    assert_equal [ "Teleportation Burst" ], mew[:attacks].map { _1[:name] }
  end

  # --- stats --------------------------------------------------------------------------------

  test "weakness and resistance carry the energy alone, without the multiplier" do
    mew = parse("30th_66")

    assert_equal "Darkness", mew[:weakness]
    assert_equal "Fighting", mew[:resistance]
  end

  test "an empty resistance block is nil" do
    assert_equal "Fighting", parse("30th_53")[:weakness]
    assert_nil parse("30th_53")[:resistance]
  end

  test "a Pokémon with an empty retreat list costs 0, never nil" do
    # Card validates retreat_cost present and >= 0 on every Pokémon, so nil is a refused card.
    assert_equal 0, parse("30th_66")[:retreat_cost]
    assert_equal 0, parse("30th_120")[:retreat_cost]
    assert_equal 1, parse("30th_21")[:retreat_cost]
  end

  test "a Trainer has no retreat cost at all, rather than 0" do
    assert_nil parse("30th_128")[:retreat_cost]
  end

  # --- trainers -----------------------------------------------------------------------------

  test "a Trainer carries its subtype and its printed text, and no Pokémon columns" do
    ultra_ball = parse("30th_128")

    assert_equal "Trainer", ultra_ball[:card_type]
    assert_equal "Item", ultra_ball[:subtype]
    assert_nil ultra_ball[:hp]
    assert_nil ultra_ball[:type_symbol]
    assert_equal(
      "You can use this card only if you discard 2 other cards from your hand.\n\n" \
      "Search your deck for a Pokémon, reveal it, and put it into your hand. Then, shuffle your deck.",
      ultra_ball[:effect]
    )
  end

  test "a Pokémon Tool is a Trainer, despite the word in its type line" do
    # Hand-edited: the real Ultra Ball fragment with only its <h2> swapped, because no captured
    # page is a Tool. Testing `/Pokémon/` before `/\ATrainer/` claimed this card, gave it stage
    # "Basic" and retreat 0, and the model then refused it complaining about missing HP.
    tool = File.read(FIXTURE_DIR.join("30th_128.html"))
      .sub("<h2>Trainer-Item</h2>", "<h2>Trainer-Pokémon Tool</h2>")
    parsed = Cards::OfficialParser.call(tool)

    assert_equal "Trainer", parsed[:card_type]
    assert_equal "Pokémon Tool", parsed[:subtype]
    assert_nil parsed[:stage]
    assert_nil parsed[:retreat_cost]
  end

  test "a Trainer's printed text is not read as a nameless attack" do
    # Its block carries an empty energy list and no name, which is what tells it apart from an
    # attack; without the name half of that test it became a zero-cost attack called nothing.
    assert_empty parse("30th_128")[:attacks]
    assert_empty parse("30th_128")[:abilities]
  end

  test "an attack whose cost cannot be read is refused, not silently made free" do
    unmapped = File.read(FIXTURE_DIR.join("30th_120.html")).sub("icon-free", "icon-sparkle")

    assert_raises(Cards::OfficialParser::ParseError) { Cards::OfficialParser.call(unmapped) }
  end

  test "a Pokémon has no effect, because its text lives on its attacks" do
    # Attack effects sit in a <pre> inside .ability — the same shape a Trainer's text uses. A
    # parser without the card-type guard writes "This attack does 30 damage…" into cards.effect
    # for all 154 Pokémon in the set.
    assert_nil parse("30th_21")[:effect]
    assert_nil parse("30th_66")[:effect]
  end

  # --- printing metadata --------------------------------------------------------------------

  test "rarity is the first token, and no vocabulary is translated" do
    assert_equal "Double", parse("30th_21")[:rarity]
    assert_equal "Futuristic", parse("30th_158")[:rarity]
    assert_equal "Classic", parse("30th-c_1")[:rarity]
  end

  test "Illustration is stored as Illustration, not folded onto Limitless's Art" do
    # This is the one rarity the decision is actually about: the official database says
    # "Illustration Rare" where Limitless says "Art Rare". The spec refuses to map it, because a
    # table would also have to invent names for Futuristic and Classic, which Limitless has not
    # given. The duplicate in the /cards filter is visible and a rescrape removes it.
    assert_equal "Illustration", parse("30th_129")[:rarity]
    assert_not_equal "Art", parse("30th_129")[:rarity]
  end

  test "reads the set name, the illustrator and the official art" do
    greninja = parse("30th_21")

    assert_equal "30th Celebration", greninja[:set_full_name]
    assert_equal "5ban Graphics", greninja[:artist]
    assert_match %r{/30TH_EN_21\.png\z}, greninja[:image_url]
  end

  test "hp is read as a number" do
    assert_equal 300, parse("30th_21")[:hp]
  end

  # --- refusal ------------------------------------------------------------------------------

  test "a fragment with no card detail raises rather than returning a blank hash" do
    # The scraper is not unit-tested, so this raise is what stands in for it: Imperva serves its
    # block page with HTTP 200, and a blank hash would be written to the database as a card.
    assert_raises(Cards::OfficialParser::ParseError) do
      Cards::OfficialParser.call("<html><body><p>Pardon Our Interruption</p></body></html>")
    end
  end
end
