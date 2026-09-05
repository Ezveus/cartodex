require "test_helper"

# Four of these tests exist because the production data proved the mechanism decisive, and two of
# those two failures are silent — a report that is simply wrong still sums to a plausible-looking
# 60. They are, in order below: a name carried by several fingerprints must stay split; two
# printings of one fingerprint in one list must be summed rather than counted twice; a card no
# category recognises must surface rather than vanish; and a tied mode must be reported as a tie
# rather than resolved by whichever value the tally happened to yield first.
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

  test "categories come in the declared display order and empty ones are dropped" do
    sample = {
      pokemon("Order Pokemon") => 1,
      trainer("Order Item", subtype: "Item") => 1,
      trainer("Order Tool", subtype: "Tool") => 1,
      energy("Order Special", subtype: "Special Energy") => 1,
      energy("Order Basic", subtype: "Basic Energy") => 1,
      trainer("Order Oddity", subtype: "Brand New Subtype") => 1
    }
    archetype = archetype_of_its_own
    record(standard_event, archetype, deck: field_list(sample))

    result = stats_for(archetype)

    assert_equal [ :pokemon, :item, :tool, :special_energy, :basic_energy, :other ],
      result.categories.map(&:key)
    assert_equal Archetypes::CardStats::CATEGORIES.to_h.values_at(
      :pokemon, :item, :tool, :special_energy, :basic_energy, :other
    ), result.categories.map(&:label)
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

  def archetype_of_its_own
    Archetype.create!(primary_card: trainer("Card Stats Marker #{next_index}"))
  end

  def pokemon(name, hp: 70)
    Card.create!(name: name, card_type: "Pokémon", set_name: SET_NAME,
                 set_number: next_index.to_s, rarity: "Common", hp: hp,
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
