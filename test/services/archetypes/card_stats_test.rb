require "test_helper"

# Several of these tests exist because the production data proved the mechanism decisive, and
# every one of those failures is silent — a report that is simply wrong still sums to a
# plausible-looking 60. They are, in order below: a name carried by several fingerprints must stay
# split; two printings of one fingerprint in one list must be summed rather than counted twice; a
# card no category recognises must surface rather than vanish; a tied mode must be reported as a
# tie rather than resolved by whichever value the tally happened to yield first; two cards with no
# fingerprint at all must not merge into one row at their sum; and the "N lists" this service
# prints must be the same number the other three services print for the same sample.
#
# The last of those spans all four services and lives here rather than in one of their files
# because this is the service whose denominator was the odd one out: it used to be counted from
# the `deck_cards` rows, which is "lists holding at least one card" and not "lists".
#
# The sample is built per test. No fixture is added: they are global, and the standings the suite
# already carries are counted elsewhere.
class Archetypes::CardStatsTest < ActiveSupport::TestCase
  test "reports inclusion, the copies played when played, and the fixed core" do
    alpha = pokemon("Alpha")
    beta = trainer("Beta", subtype: "Supporter")
    gamma = trainer("Gamma", subtype: "Item")
    archetype = archetype_of_its_own
    event = standard_event

    record(event, archetype, deck: field_list(alpha => 4, beta => 3, gamma => 2))
    record(event, archetype, deck: field_list(alpha => 4, beta => 3))
    record(event, archetype, deck: field_list(alpha => 4, beta => 4, gamma => 2))
    record(event, archetype, deck: field_list(alpha => 4, beta => 4, gamma => 3))
    # A standing with no list is not part of the report's sample. Note that SQL's NULL semantics
    # already exclude it from `deck_id IN (…)`, so this documents the contract rather than
    # locking the service's own `where.not(deck_id: nil)` — removing that filter leaves this
    # green, which was verified.
    record(event, archetype)

    result = stats_for(archetype)

    assert_predicate result, :any?
    assert_equal 4, result.lists_count

    entry = entry_named(result, "Alpha")
    assert_equal [ 4, 100.0, 4, 4, [ 4 ] ],
      [ entry.inclusion_count, entry.inclusion_pct, entry.min_copies, entry.max_copies, entry.modes ]
    assert entry.core
    assert_predicate entry, :fixed?

    # Played by every list but not always in the same number: core, and deliberately not fixed.
    entry = entry_named(result, "Beta")
    assert_equal [ 4, 100.0, 3, 4 ],
      [ entry.inclusion_count, entry.inclusion_pct, entry.min_copies, entry.max_copies ]
    assert entry.core
    refute_predicate entry, :fixed?
    refute_predicate entry, :single_quantity?

    # min/max are the range *when played* — the list that plays none of it is not a zero in the
    # range, it is outside the sample the range describes.
    entry = entry_named(result, "Gamma")
    assert_equal [ 3, 75.0, 2, 3, [ 2 ] ],
      [ entry.inclusion_count, entry.inclusion_pct, entry.min_copies, entry.max_copies, entry.modes ]
    refute entry.core
    refute_predicate entry, :fixed?

    assert_equal [ 1, 4 ], [ result.fixed_core_cards, result.fixed_core_copies ]
  end

  # Eleven lists at three copies and eleven at four is not "three". Reporting one of them would
  # state a consensus the sample does not hold, and nothing downstream could tell.
  test "a tied mode is reported as a tie, never resolved in silence" do
    tied = trainer("Tied Item", subtype: "Item")
    settled = trainer("Settled Item", subtype: "Item")
    archetype = archetype_of_its_own
    event = standard_event

    record(event, archetype, deck: field_list(tied => 2, settled => 1))
    record(event, archetype, deck: field_list(tied => 2, settled => 1))
    record(event, archetype, deck: field_list(tied => 3, settled => 2))
    record(event, archetype, deck: field_list(tied => 3, settled => 1))

    result = stats_for(archetype)

    entry = entry_named(result, "Tied Item")
    assert_equal [ 2, 3 ], entry.modes
    assert_predicate entry, :tied_mode?

    entry = entry_named(result, "Settled Item")
    assert_equal [ 1 ], entry.modes
    refute_predicate entry, :tied_mode?
  end

  # The Hoothoot case: three genuinely different cards sharing one name (in production, TEF 126 at
  # 70 HP, PRE 77 at 80 HP and SCR 114 at 70 HP with other attacks). A player chooses between them,
  # so the fingerprint must refuse to fold them — and the name-level share must stay a distinct
  # count of lists, because the third list here plays two of the three versions.
  test "a name carried by several fingerprints stays split, and its lists are counted once each" do
    first = pokemon("Hoothoot", hp: 70)
    second = pokemon("Hoothoot", hp: 80)
    third = pokemon("Hoothoot", hp: 90)
    assert_equal 3, [ first, second, third ].map(&:fingerprint).uniq.size

    archetype = archetype_of_its_own
    event = standard_event
    record(event, archetype, deck: field_list(first => 2))
    record(event, archetype, deck: field_list(second => 1))
    record(event, archetype, deck: field_list(first => 1, third => 1))

    result = stats_for(archetype)
    group = group_named(result, "Hoothoot")

    assert_predicate group, :split?
    assert_equal 3, group.entries.size
    assert_equal [ first, second, third ].map(&:fingerprint).sort, group.entries.map(&:fingerprint).sort

    # Three lists play some Hoothoot; the four printing-level inclusions add up to more, because
    # one list plays two versions. The name-level number is the smaller, honest one.
    assert_equal 4, group.entries.sum(&:inclusion_count)
    assert_equal 3, group.inclusion_count
    assert_in_delta 100.0, group.inclusion_pct, 0.01
    assert_equal 3, result.lists_count
  end

  # (deck_id, card_id) is UNIQUE, so two printings of one card in one list are two perfectly legal
  # rows. Counted separately the card appears in more lists than exist, each at a fraction of its
  # copies, and nothing raises.
  test "two printings of one fingerprint in one list are summed, not counted twice" do
    first = pokemon("Squawkabilly", hp: 90)
    second = pokemon("Squawkabilly", hp: 90)
    assert_equal first.fingerprint, second.fingerprint
    refute_equal first.id, second.id

    archetype = archetype_of_its_own
    event = standard_event
    record(event, archetype, deck: field_list(first => 2, second => 2))
    record(event, archetype, deck: field_list(first => 4))

    result = stats_for(archetype)
    group = group_named(result, "Squawkabilly")
    entry = group.entries.sole

    assert_equal 2, result.lists_count
    assert_equal 2, entry.inclusion_count
    assert_equal [ 4, 4 ], [ entry.min_copies, entry.max_copies ]
    assert_equal [ 4 ], entry.modes
    assert_predicate entry, :fixed?
    assert_equal [ 1, 4 ], [ result.fixed_core_cards, result.fixed_core_copies ]
  end

  # `subtype` is a free scraped string. A value the table does not know must arrive as a labelled
  # bucket rather than being dropped from a report that would still look complete.
  test "a card no category recognises surfaces in Other rather than vanishing" do
    known = pokemon("Categorised Pokemon")
    odd = trainer("Mystery Gadget", subtype: "Brand New Subtype")
    archetype = archetype_of_its_own
    record(standard_event, archetype, deck: field_list(known => 1, odd => 2))

    result = stats_for(archetype)
    other = result.categories.find { |category| category.key == :other }

    assert_not_nil other, "an uncategorisable card must not disappear from the report"
    assert_equal "Other", other.label
    assert_equal [ "Mystery Gadget" ], other.name_groups.map(&:name)
    assert_equal 1, other.cards_count
  end

  # Cards::Fetcher#parse_subtype can emit either spelling — it reads whatever follows "Trainer - "
  # — so both have to land in one bucket or the same card splits in two.
  test "both spellings of the tool subtype land in the Tool category" do
    short = trainer("Ancient Booster Energy Capsule", subtype: "Tool")
    long = trainer("Bravery Charm", subtype: "Pokémon Tool")
    archetype = archetype_of_its_own
    record(standard_event, archetype, deck: field_list(short => 1, long => 1))

    result = stats_for(archetype)
    tool = result.categories.find { |category| category.key == :tool }

    assert_equal [ "Ancient Booster Energy Capsule", "Bravery Charm" ], tool.name_groups.map(&:name)
    assert_equal [ :tool ], result.categories.map(&:key)
  end

  # Every category at once, Supporter and Stadium included. An earlier version of this test left
  # both out, which made it blind to the one permutation a reader would actually get wrong:
  # Tool and Stadium are adjacent, they are the pair CLAUDE.md and Archetypes::CardReport each
  # named in the opposite order, and swapping them in CATEGORIES passed a sample holding neither.
  test "categories come in the declared display order and empty ones are dropped" do
    sample = {
      pokemon("Order Pokemon") => 1,
      trainer("Order Supporter", subtype: "Supporter") => 1,
      trainer("Order Item", subtype: "Item") => 1,
      trainer("Order Tool", subtype: "Tool") => 1,
      trainer("Order Stadium", subtype: "Stadium") => 1,
      energy("Order Special", subtype: "Special Energy") => 1,
      energy("Order Basic", subtype: "Basic Energy") => 1,
      trainer("Order Oddity", subtype: "Brand New Subtype") => 1
    }
    archetype = archetype_of_its_own
    record(standard_event, archetype, deck: field_list(sample))

    result = stats_for(archetype)

    # Spelled out rather than compared against CATEGORIES.map(&:first): read off the constant, the
    # assertion agrees with whatever order the constant happens to hold and pins nothing.
    assert_equal [ :pokemon, :supporter, :item, :tool, :stadium, :special_energy, :basic_energy,
                   :other ], result.categories.map(&:key)
    assert_equal [ "Pokémon", "Supporter", "Item", "Tool", "Stadium", "Special Energy",
                   "Basic Energy", "Other" ], result.categories.map(&:label)
  end

  # A category with nothing in it is dropped, which is what makes the order test above worth
  # asserting on a full sample rather than on a partial one.
  test "a category the sample does not reach is absent rather than empty" do
    archetype = archetype_of_its_own
    record(standard_event, archetype, deck: field_list(pokemon("Lonely Pokemon") => 2))

    assert_equal [ :pokemon ], stats_for(archetype).categories.map(&:key)
  end

  # `compute_fingerprint` is a before_save, so only a write that bypasses callbacks can leave a
  # card without one — update_column, insert_all, a fixture. The failure is silent and total: SQL
  # gathers **every** NULL into one group, so a bare `GROUP BY cards.fingerprint` folds two such
  # cards into a single row whose copies are their sum and whose name is whichever the query
  # picked. The other card is simply gone from a report that still sums to a plausible 60, and
  # nothing raises.
  test "two cards with no fingerprint stay two rows rather than merging into their sum" do
    ghost_supporter = trainer("Ghost Supporter", subtype: "Supporter")
    ghost_item = trainer("Ghost Item", subtype: "Item")
    [ ghost_supporter, ghost_item ].each { |card| card.update_column(:fingerprint, nil) }
    settled = pokemon("Fingerprinted Pokemon")

    archetype = archetype_of_its_own
    event = standard_event
    record(event, archetype, deck: field_list(ghost_supporter => 4, ghost_item => 3, settled => 2))
    record(event, archetype, deck: field_list(ghost_supporter => 4, settled => 2))

    result = stats_for(archetype)

    assert_equal 2, result.lists_count

    # Merged, this one reads 7 copies in the first list — the Supporter's 4 plus the Item's 3.
    supporter = entry_named(result, "Ghost Supporter")
    assert_equal [ 2, 4, 4 ],
      [ supporter.inclusion_count, supporter.min_copies, supporter.max_copies ]

    # And this one does not exist at all: MIN() picked the other name, and the report lost a card
    # without losing its plausibility.
    item = entry_named(result, "Ghost Item")
    assert_equal [ 1, 3, 3 ], [ item.inclusion_count, item.min_copies, item.max_copies ]

    # Each under its own subtype's heading, which the merged row could only have been under one of.
    assert_equal [ :pokemon, :supporter, :item ], result.categories.map(&:key)
  end

  # The page prints one "N lists" above the selector, another beside the performance panel, and a
  # third as the denominator of every percentage in the report; the index prints a fourth for the
  # same archetype. They are four services, and the sample below is the shape that used to split
  # them: a list holding no card at all (the report used to count lists from `deck_cards` rows, so
  # it did not see this one) and two standings pointing at one deck (`index_tournament_standings_
  # on_deck_id` is not unique, so a bare COUNT(deck_id) saw it twice).
  test "the four list counters agree on a sample built to split them" do
    archetype = archetype_of_its_own
    event = standard_event
    shared_list = field_list(pokemon("Shared Card") => 3)

    # One deck, two standings — two players at the same event registering the same 60 cards.
    record(event, archetype, deck: shared_list)
    record(event, archetype, deck: shared_list)
    # A list with no cards: an import that resolved no printing, or a row typed and left blank.
    record(event, archetype, deck: field_list({}))
    # And a standing with no list at all, which no counter may include.
    record(event, archetype)

    standings = TournamentStanding.where(archetype_id: archetype.id)
    scope = Archetypes::MetagameScope.call(archetype: archetype)
    report = Archetypes::CardStats.call(standings: scope.listed_standings)
    performance = Archetypes::Performance.call(standings: scope.standings)
    index = Archetypes::IndexCounts.call(archetype_ids: [ archetype.id ]).fetch(archetype.id)

    assert_equal 4, standings.count, "sanity: four standings, three of which carry a list"
    assert_equal [ 2, 2, 2, 2 ],
      [ scope.lists_count, report.lists_count, performance.lists_count, index.lists ],
      "the sample selector, the report, the panel and the index row must print one number"
    # The other half of the same claim: the standings count is not the list count, and the gap the
    # panel names is the two rows without a list of their own.
    assert_equal [ 4, 4 ], [ performance.standings_count, index.standings ]
    assert_equal 2, performance.unlisted_count
  end

  # `set_number` is a String holding a number most of the time and something like "SV107" the
  # rest, so the printings of one name are ordered numerically first. A plain String sort puts
  # "114" above "77", which is a printing order no set list has.
  test "the printings of one name are ordered by set number as a number, not as a string" do
    early = pokemon("Numbered Owl", hp: 70, set_number: "77")
    late = pokemon("Numbered Owl", hp: 80, set_number: "114")
    refute_equal early.fingerprint, late.fingerprint, "sanity: two printings, two cards"

    archetype = archetype_of_its_own
    # Both in the one list, so the two entries tie on inclusion and the set number is what is
    # left to order them by.
    record(standard_event, archetype, deck: field_list(early => 1, late => 1))

    group = group_named(stats_for(archetype), "Numbered Owl")

    assert_equal [ 1, 1 ], group.entries.map(&:inclusion_count), "sanity: the entries tie"
    assert_equal [ "77", "114" ], group.entries.map { |entry| entry.card.set_number }
  end

  test "a sample with no lists yields an empty result without raising" do
    archetype = archetype_of_its_own
    record(standard_event, archetype)

    result = stats_for(archetype)

    assert_equal 0, result.lists_count
    assert_equal [], result.categories
    assert_equal [ 0, 0 ], [ result.fixed_core_cards, result.fixed_core_copies ]
    refute_predicate result, :any?
  end

  test "an entry carries the type labels of the card it reports" do
    label = CardLabel.create!(slug: "ace-spec", name: "ACE SPEC", family: "type", position: 10)
    card = cards(:honedge)
    label.assignments.create!(fingerprint: card.fingerprint, card: card, source: "imported")

    entry = entry_for(card)

    assert_equal [ "ACE SPEC" ], entry.labels.map(&:name)
  end

  # A human's refusal is a row, not an absence, and the report must read it as the refusal it is.
  test "a rejected assignment is not a label" do
    label = CardLabel.create!(slug: "ace-spec", name: "ACE SPEC", family: "type", position: 10)
    card = cards(:honedge)
    label.assignments.create!(fingerprint: card.fingerprint, source: "curated", rejected: true)

    assert_empty entry_for(card).labels
  end

  # Every card here carries its own distinct label, on purpose: ten cards sharing one label would
  # repeat the identical "card_labels WHERE id = ?" statement, which the per-request query cache
  # serves after the first and count_queries never sees — hiding the exact N+1 this test exists
  # to catch. Distinct labels mean distinct SQL, so a query that runs once per card rather than
  # once for the whole report cannot hide behind the cache.
  test "labels cost one query however many cards the report holds" do
    archetype = archetype_of_its_own
    event = standard_event

    record(event, archetype, deck: field_list(label_card(pokemon("Query Card")) => 1))
    one_card_queries = capture_queries { stats_for(archetype) }

    extra_cards = 9.times.map { |i| label_card(pokemon("Query Card Extra #{i}")) }
    record(event, archetype, deck: field_list(extra_cards.index_with { 1 }))
    ten_card_queries = capture_queries { stats_for(archetype) }

    assert_equal one_card_queries.size, ten_card_queries.size
    assert_equal 1, one_card_queries.count { |sql| sql.include?("card_label") }
    assert_equal 1, ten_card_queries.count { |sql| sql.include?("card_label") }
  end

  # Helpers below `private`, where a `test` declaration would never run.
  private

  SET_NAME = "CST".freeze

  def stats_for(archetype)
    Archetypes::CardStats.call(standings: TournamentStanding.where(archetype_id: archetype.id))
  end

  def group_named(result, name)
    result.categories.flat_map(&:name_groups).find { |group| group.name == name } ||
      flunk("no name group for #{name.inspect}")
  end

  def entry_named(result, name)
    group_named(result, name).entries.sole
  end

  # An archetype and a single-list sample built purely to read one card's report entry back — the
  # label tests care about `Entry#labels`, not about inclusion or copies, so one list of one card
  # is the whole fixture.
  def entry_for(card)
    archetype = Archetype.create!(primary_card: card)
    record(standard_event, archetype, deck: field_list(card => 1))

    entry_named(stats_for(archetype), card.name)
  end

  # A fresh label per call, not one shared across cards — see the query-count test above for why
  # that distinctness is load-bearing. Hands the card straight back, so it chains inside a
  # `field_list(...)` call the way a bare card does.
  def label_card(card)
    index = next_index
    label = CardLabel.create!(slug: "query-label-#{index}", name: "Query Label #{index}",
                               family: "type", position: index)
    label.assignments.create!(fingerprint: card.fingerprint, card: card, source: "imported")
    card
  end

  def archetype_of_its_own
    Archetype.create!(primary_card: trainer("Card Stats Marker #{next_index}"))
  end

  # `set_number` is a String on purpose, and takeable: it is what the printings of one name are
  # ordered by, and "77" against "114" is the pair that tells a numeric sort from a lexical one.
  def pokemon(name, hp: 70, set_number: nil)
    Card.create!(name: name, card_type: "Pokémon", set_name: SET_NAME,
                 set_number: set_number || next_index.to_s, rarity: "Common", hp: hp,
                 type_symbol: "Grass", retreat_cost: 1, stage: "Basic")
  end

  def trainer(name, subtype: "Item")
    Card.create!(name: name, card_type: "Trainer", set_name: SET_NAME,
                 set_number: next_index.to_s, rarity: "Uncommon", subtype: subtype)
  end

  def energy(name, subtype:)
    Card.create!(name: name, card_type: "Energy", set_name: SET_NAME,
                 set_number: next_index.to_s, subtype: subtype,
                 rarity: (subtype == "Basic Energy" ? nil : "Uncommon"))
  end

  def standard_event(date: Date.new(2026, 5, 1))
    Tournament.create!(name: "Card Stats Event #{next_index}", date: date, format: "standard",
                       standard_pool: standard_pools(:twm_por), tier: "regional",
                       created_by: users(:one))
  end

  def record(event, archetype, deck: nil)
    TournamentStanding.create!(tournament: event, archetype: archetype, deck: deck,
                               player_name: "Player #{next_index}", division: "masters",
                               created_by: users(:one))
  end

  def field_list(copies_by_card)
    Deck.create!(name: "Field list #{next_index}", user: nil, shared: true, physical: false,
                 format: "glc").tap do |deck|
      copies_by_card.each { |card, copies| deck.deck_cards.create!(card: card, quantity: copies) }
    end
  end

  def next_index
    @next_index = @next_index.to_i + 1
  end
end
