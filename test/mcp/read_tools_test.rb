require "test_helper"
require "json"

class ReadToolsTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @context = { user: @user }
  end

  def payload(response)
    JSON.parse(response.content.first[:text])
  end

  test "SearchCardsTool finds cards by name substring" do
    response = SearchCardsTool.call(query: "honed", server_context: @context)
    names = payload(response).map { |c| c["name"] }

    assert_includes names, "Honedge"
  end

  test "SearchCardsTool treats an underscore in the query as a literal, not a wildcard" do
    assert_includes payload(SearchCardsTool.call(query: "budew", server_context: @context)).map { |c| c["name"] },
      "Budew", "sanity: the unescaped spelling must match"

    response = SearchCardsTool.call(query: "b_dew", server_context: @context)

    assert_empty payload(response)
  end

  test "SearchCardsTool treats a percent sign in the query as a literal, not a wildcard" do
    response = SearchCardsTool.call(query: "bud%w", server_context: @context)

    assert_empty payload(response)
  end

  test "ListDecksTool returns only the user's decks" do
    response = ListDecksTool.call(server_context: @context)
    keys = payload(response).map { |d| d["key"] }

    assert_includes keys, decks(:one).key
    assert_not_includes keys, decks(:two).key
  end

  test "ListDecksTool names the Standard pool a deck is anchored to" do
    response = ListDecksTool.call(server_context: @context)
    deck = payload(response).find { |d| d["key"] == decks(:one).key }

    assert_equal "TWM-POR", deck["standard_pool"]
  end

  test "ListCollectionTool returns the user's collection entries" do
    response = ListCollectionTool.call(server_context: @context)
    card_ids = payload(response).map { |c| c["card_id"] }

    assert_includes card_ids, cards(:honedge).id
  end

  test "ListDeckCardsTool returns the cards in an owned deck" do
    response = ListDeckCardsTool.call(deck_key: decks(:one).key, server_context: @context)
    card_ids = payload(response).map { |c| c["card_id"] }

    assert_includes card_ids, cards(:honedge).id
  end

  test "ListDeckCardsTool reports an error for a deck the user does not own" do
    response = ListDeckCardsTool.call(deck_key: decks(:two).key, server_context: @context)

    assert_match(/Error/i, response.content.first[:text])
  end

  test "SearchCardsTool finds a card when set_code is given in lowercase" do
    response = SearchCardsTool.call(query: "honed", set_code: "por", server_context: @context)
    names = payload(response).map { |c| c["name"] }

    assert_includes names, "Honedge"
  end

  test "SearchCardsTool finds a card when set_code is given in uppercase" do
    response = SearchCardsTool.call(query: "honed", set_code: "POR", server_context: @context)
    names = payload(response).map { |c| c["name"] }

    assert_includes names, "Honedge"
  end

  test "SearchCardsTool clamps a limit of 0 up to at least 1 result" do
    response = SearchCardsTool.call(query: "honed", limit: 0, server_context: @context)
    results = payload(response)

    assert_operator results.size, :>=, 1
    assert_operator results.size, :<=, 1
  end

  # The call shape the feature exists for: a player reading a stack of cards knows
  # the set and the number and not the name.
  test "SearchCardsTool finds a printing from its set code and collector number alone" do
    response = SearchCardsTool.call(set_code: "por", set_number: "56", server_context: @context)

    assert_equal [ cards(:honedge).id ], payload(response).map { |c| c["id"] }
  end

  # `.to_s` alone is invisible here: cards.set_number is a string column, so Active
  # Record already renders where(set_number: 56) as `= '56'` and an implementation
  # with no coercion at all passes the integer test. The fold is the observable half,
  # and " 56 " is what a copy-paste actually delivers.
  test "SearchCardsTool folds whitespace around set_number" do
    response = SearchCardsTool.call(set_number: " 56 ", server_context: @context)

    assert_equal [ cards(:froakie_twm).id, cards(:honedge).id ].sort,
      payload(response).map { |c| c["id"] }.sort
  end

  # squish and not strip: String#strip folds ASCII whitespace only, and U+00A0 is
  # exactly what a copy-paste out of a web page carries. NameNormalizable folds the
  # same Unicode class on the name side, so the two halves of one lookup agree.
  test "SearchCardsTool folds a non-breaking space in set_code and set_number" do
    nbsp = " "

    response = SearchCardsTool.call(set_code: "#{nbsp}por#{nbsp}", set_number: "#{nbsp}56#{nbsp}",
      server_context: @context)

    assert_equal [ cards(:honedge).id ], payload(response).map { |c| c["id"] }
  end

  # A LIKE '%5%' implementation answers this with POR 56 and TWM 56 as well.
  test "SearchCardsTool matches set_number exactly, not as a substring" do
    response = SearchCardsTool.call(set_number: "5", server_context: @context)

    assert_equal [ cards(:basic_psychic_energy).id ], payload(response).map { |c| c["id"] }
  end

  # No printing in the catalogue carries a leading zero, so there is no padding to
  # normalise and "056" is a number nothing is filed under.
  test "SearchCardsTool does not normalise a zero-padded set_number" do
    assert_empty payload(SearchCardsTool.call(set_number: "056", server_context: @context))
  end

  # No fixture carries a non-numeric collector number, so `.to_i` — or the
  # CAST(set_number AS INTEGER) both card indexes already use in their ORDER BY —
  # is bit-identical to text matching on every other row in this file.
  test "SearchCardsTool matches a non-numeric collector number as text" do
    CardSet.create!(code: "CRZ", name: "Crown Zenith", release_date: Date.new(2023, 1, 20))
    gallery_card = Card.create!(name: "Bidoof", card_type: "Pokémon", set_name: "CRZ",
      set_number: "GG12", rarity: "Illustration Rare",
      hp: 70, stage: "Basic", type_symbol: "Colorless", retreat_cost: 1)

    response = SearchCardsTool.call(set_code: "CRZ", set_number: "GG12", server_context: @context)

    assert_equal [ gallery_card.id ], payload(response).map { |c| c["id"] }
  end

  # PAL has no card_sets row at all, so this also refuses the half-fix that resolves
  # the code through that table before filtering on it. The Froakie row below does
  # not: card_sets(:twm) exists.
  test "SearchCardsTool finds a card whose set was never imported" do
    response = SearchCardsTool.call(set_code: "PAL", set_number: "172", server_context: @context)

    assert_equal [ cards(:trainer_card).id ], payload(response).map { |c| c["id"] }
  end

  # card_sets(:twm) exists but this card is not linked to it, which is exactly what
  # the old joins(:card_set) dropped.
  test "SearchCardsTool finds a card that carries no card_set link" do
    response = SearchCardsTool.call(set_code: "twm", set_number: "56", server_context: @context)

    assert_equal [ cards(:froakie_twm).id ], payload(response).map { |c| c["id"] }
  end

  # A `nil?` guard lets "" through, and Card.name_matching("") compiles to LIKE '%%':
  # 20 arbitrary cards answered to a call that named no criterion at all.
  test "SearchCardsTool refuses a call whose every criterion is blank" do
    text = SearchCardsTool.call(query: "", set_code: "", set_number: "  ", server_context: @context)
      .content.first[:text]

    assert_equal "Error: give at least one of query, set_code or set_number.", text
    assert_raises(JSON::ParserError, "the refusal must not also be a JSON array") { JSON.parse(text) }
  end

  # isError is the only field a client can read without parsing English: `text("Error: …")`
  # and `text("[]")` are byte-identical on it, and the gem's own "Missing required arguments"
  # — which this refusal replaces — sets it. Answering a refusal as a success is how a client
  # ends up treating "you gave me no criterion" as "no such card exists".
  test "SearchCardsTool's refusal is flagged as an error and an empty result is not" do
    refusal = SearchCardsTool.call(server_context: @context)
    empty = SearchCardsTool.call(set_code: "POR", set_number: "99999", server_context: @context)

    assert_equal [], payload(empty), "sanity: this call succeeds and matches nothing"
    assert_not empty.to_h[:isError], "an empty result is not an error"
    assert empty.to_h.key?(:isError), "sanity: the flag is on the wire at all"
    assert refusal.to_h[:isError], "the refusal must be distinguishable without parsing its text"
  end

  # Over the wire both refusals are a 200 with one text block, so the integration
  # test cannot see this declaration; only a direct read of the schema can.
  test "SearchCardsTool requires no argument" do
    assert_empty SearchCardsTool.input_schema.to_h[:required]
  end

  test "SearchCardsTool declares set_number as a string or an integer" do
    assert_equal [ "string", "integer" ],
      SearchCardsTool.input_schema.to_h.dig(:properties, :set_number, :type)
  end

  # Nothing in the suite reads a description, so shipping the old one leaves the
  # argument in place while no assistant can discover it — with a green suite.
  test "SearchCardsTool's description names set_number" do
    assert_match(/set_number/, SearchCardsTool.description_value)
  end

  # Every other test here reads ["name"] only, so `id` — the key a client chains
  # into add_card_to_collection — could be dropped without a single failure.
  test "SearchCardsTool returns the whole documented payload for a row" do
    response = SearchCardsTool.call(set_code: "POR", set_number: "56", server_context: @context)

    assert_equal({ "id" => cards(:honedge).id, "name" => "Honedge", "set_name" => "POR",
                   "set_number" => "56", "card_type" => "Pokémon" }, payload(response).first)
  end

  # Both bounds survived mutation before this test existed: MAX_LIMIT could be raised to 500 and
  # the default dropped to 3 with the whole suite green, because no fixture set is big enough for
  # either to bite. They are what stops a set-code-only call — a shape `required: []` newly makes
  # reachable — from serialising the catalogue, and what the description promises a client.
  test "SearchCardsTool defaults to 20 results and caps at MAX_LIMIT" do
    51.times { |i| Card.create!(name: "Bulk Filler #{i}", card_type: "Trainer", set_name: "ZZY", set_number: i.to_s, rarity: "Common") }

    assert_equal 20, payload(SearchCardsTool.call(query: "bulk filler", server_context: @context)).size,
      "no limit given must answer 20, not everything and not 3"
    assert_equal MAX_LIMIT_EXPECTED,
      payload(SearchCardsTool.call(query: "bulk filler", limit: 500, server_context: @context)).size,
      "a limit above the cap must be reduced to it, not honoured"
    assert_equal 5, payload(SearchCardsTool.call(query: "bulk filler", limit: 5, server_context: @context)).size,
      "a limit below the cap is honoured"
  end

  # Spelled out rather than read off SearchCardsTool::MAX_LIMIT: a test that asks the
  # implementation for its own bound agrees with it whatever it becomes.
  MAX_LIMIT_EXPECTED = 50

  # An implementation that reassigns from Card.all per filter instead of chaining
  # answers the last criterion alone, and would still find Honedge under a name it
  # does not carry.
  test "SearchCardsTool ANDs query, set_code and set_number together" do
    matching = SearchCardsTool.call(query: "honed", set_code: "POR", set_number: "56", server_context: @context)

    assert_equal [ cards(:honedge).id ], payload(matching).map { |c| c["id"] }

    mismatched = SearchCardsTool.call(query: "budew", set_code: "POR", set_number: "56", server_context: @context)

    assert_empty payload(mismatched), "the name must narrow the set and number, not be replaced by them"
  end

  test "ListCollectionTool with a matching query returns that entry" do
    response = ListCollectionTool.call(query: "honed", server_context: @context)
    card_ids = payload(response).map { |c| c["card_id"] }

    assert_includes card_ids, cards(:honedge).id
  end

  test "ListCollectionTool with a non-matching query returns an empty array" do
    response = ListCollectionTool.call(query: "zzz_no_such_card", server_context: @context)

    assert_equal [], payload(response)
  end

  # The filter moved from Ruby into SQL, which means it now goes through
  # Card.name_matching and inherits its metacharacter escaping.
  test "ListCollectionTool treats LIKE metacharacters in the query as literals" do
    @user.collections.find_or_create_by!(card: cards(:budew_pre)) { |c| c.quantity = 0 }.update!(quantity: 1)

    assert_includes payload(ListCollectionTool.call(query: "budew", server_context: @context)).map { |c| c["name"] },
      "Budew", "sanity: the unescaped spelling must match"

    assert_equal [], payload(ListCollectionTool.call(query: "b_dew", server_context: @context)),
      "_ must not act as a wildcard"
    assert_equal [], payload(ListCollectionTool.call(query: "bud%w", server_context: @context)),
      "% must not act as a wildcard"
  end

  # The tool promises a case-insensitive substring, and filtering in SQL must not
  # quietly narrow that to ASCII: SQLite's LIKE folds only A–Z, so matching on
  # `name` would miss an accented letter typed in the other case.
  test "ListCollectionTool matches an accented name whatever the case typed" do
    cards(:honedge).update!(name: "Flabébé")

    %w[Flabébé FLABÉBÉ flabébé BÉBÉ].each do |query|
      names = payload(ListCollectionTool.call(query: query, server_context: @context)).map { |c| c["name"] }

      assert_includes names, "Flabébé", "#{query.inspect} must match"
    end
  end

  # The point of batching: one collection entry or many must cost the same.
  test "ListCollectionTool issues a constant number of queries regardless of collection size" do
    one = count_queries { ListCollectionTool.call(server_context: @context) }

    grow_collection(@user)

    many = count_queries { ListCollectionTool.call(server_context: @context) }

    assert_equal one, many, "query count grew with the collection: #{one} -> #{many}"
  end

  # Each deck reports its pool's name, and StandardPool#name reads both of the pool's card-set
  # bounds — a pool per deck on purpose, since decks sharing one issue identical SQL that the
  # query cache serves and count_queries does not see.
  test "ListDecksTool issues a constant number of queries regardless of how many decks" do
    @user.decks.create!(name: "Extra 0", standard_pool: pool_of_its_own(0))

    one = count_queries { ListDecksTool.call(server_context: @context) }

    (1..4).each { |i| @user.decks.create!(name: "Extra #{i}", standard_pool: pool_of_its_own(i)) }

    many = count_queries { ListDecksTool.call(server_context: @context) }

    assert_equal one, many, "query count grew with the deck count: #{one} -> #{many}"
  end

  test "ListDeckCardsTool exposes owned_copies and proxies" do
    physical = @user.decks.create!(name: "Phys", physical: true, standard_pool: standard_pools(:twm_por))
    @user.collections.find_or_create_by!(card: cards(:honedge)).update!(quantity: 1)
    physical.deck_cards.create!(card: cards(:honedge), quantity: 3, owned_copies: 1)

    response = ListDeckCardsTool.call(deck_key: physical.key, server_context: @context)
    entry = payload(response).find { |c| c["card_id"] == cards(:honedge).id }

    assert_equal 3, entry["quantity"]
    assert_equal 1, entry["owned_copies"]
    assert_equal 2, entry["proxies"]
  end

  test "ListCollectionTool exposes owned, committed and available" do
    card = cards(:honedge)
    @user.collections.find_or_create_by!(card: card).update!(quantity: 3)
    deck = @user.decks.create!(name: "Phys", physical: true, standard_pool: standard_pools(:twm_por))
    deck.deck_cards.create!(card: card, quantity: 2, owned_copies: 2)

    response = ListCollectionTool.call(server_context: @context)
    entry = payload(response).find { |c| c["card_id"] == card.id }

    assert_equal 3, entry["owned"]
    assert_equal 2, entry["committed"]
    assert_equal 1, entry["available"]
  end

  test "ListOverAllocationsTool reports over-committed cards" do
    card = cards(:honedge)
    @user.collections.find_or_create_by!(card: card).update!(quantity: 1)
    deck = @user.decks.create!(name: "Phys", physical: true, standard_pool: standard_pools(:twm_por))
    deck.deck_cards.create!(card: card, quantity: 2, owned_copies: 2)

    response = ListOverAllocationsTool.call(server_context: @context)
    card_ids = payload(response).map { |e| e["card_id"] }

    assert_includes card_ids, card.id
  end

  test "SuggestOwnedEquivalentsTool lists owned equivalent printings" do
    @user.collections.find_or_create_by!(card: cards(:budew_pre)).update!(quantity: 2)

    response = SuggestOwnedEquivalentsTool.call(card_id: cards(:budew_asc).id, server_context: @context)
    card_ids = payload(response).map { |e| e["card_id"] }

    assert_includes card_ids, cards(:budew_pre).id
  end

  test "ListPrintingsTool lists printings the user does not own" do
    response = ListPrintingsTool.call(card_id: cards(:budew_asc).id, server_context: @context)
    entry = payload(response).find { |p| p["card_id"] == cards(:budew_pre).id }

    assert_equal 0, entry["owned"], "the unowned printing is listed, not filtered out"
    assert_nil entry["real_after"], "with no deck there is no swap to project"
  end

  test "ListPrintingsTool projects the swap against a deck when given one" do
    deck = @user.decks.create!(name: "Phys", physical: true, standard_pool: standard_pools(:twm_por))
    deck.deck_cards.create!(card: cards(:budew_asc), quantity: 3)

    response = ListPrintingsTool.call(card_id: cards(:budew_asc).id, deck_key: deck.key, server_context: @context)
    entry = payload(response).find { |p| p["card_id"] == cards(:budew_pre).id }

    assert_equal 3, entry["proxies_after"]
  end

  test "ListPrintingsTool reports an unknown card id" do
    response = ListPrintingsTool.call(card_id: -1, server_context: @context)

    assert_match(/Error/i, response.content.first[:text])
  end

  test "list_decks identifies each deck by its key" do
    # This file's setup defines @user only; the deck is fetched here.
    deck = decks(:one)

    response = ListDecksTool.call(server_context: @context)

    decks = payload(response)
    assert_equal [ deck.key ], decks.map { |d| d["key"] }
    assert_nil decks.first["id"]
  end

  test "list_over_allocations carries the key of every deck it names" do
    over_allocate(cards(:honedge), owned: 1, committed: 2)

    response = ListOverAllocationsTool.call(server_context: @context)

    report = payload(response)
    assert report.first["decks"].all? { |d| d["key"].present? }, "a named deck had no key"
  end

  def pool_of_its_own(index)
    set = CardSet.create!(code: "M#{index}", name: "Mcp Set #{index}", release_date: Date.new(2025, 1, 1))
    StandardPool.create!(
      first_card_set: card_sets(:twm), last_card_set: set, regulation_marks: %w[G H],
      released_on: Date.new(2025, 1, 1) + index, legal_on: Date.new(2025, 2, 1) + index
    )
  end
end
