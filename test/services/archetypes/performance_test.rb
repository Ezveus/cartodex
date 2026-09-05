require "test_helper"

# The panel counts *all* standings in scope, including the ones nobody typed a decklist for — a
# recorded placement is a result whether or not the list survives. That is the one number the card
# report may not borrow, and the first test here is what keeps the two apart.
#
# The sample is built per test, never fixtured.
class Archetypes::PerformanceTest < ActiveSupport::TestCase
  test "counts every standing, and the listed ones separately" do
    archetype = archetype_of_its_own
    recent = standard_event(date: Date.new(2026, 5, 1))
    older = standard_event(date: Date.new(2025, 6, 1))
    record(recent, archetype, deck: field_list, placement: 1)
    record(recent, archetype, placement: 5)
    record(older, archetype, deck: field_list, placement: 12)

    result = performance_for(archetype)

    assert_predicate result, :any?
    assert_equal 3, result.standings_count
    assert_equal 2, result.events_count
    assert_equal 2, result.lists_count
    assert_equal 1, result.unlisted_count
    assert_equal 1, result.best_placement
  end

  # SQLite hands MIN()/MAX() over a date column back as a String — an aggregate carries no column
  # type for Rails to cast from — so the conversion has to happen here or the page prints "2026-05-01".
  test "the period covered comes back as Dates" do
    archetype = archetype_of_its_own
    record(standard_event(date: Date.new(2025, 6, 1)), archetype)
    record(standard_event(date: Date.new(2026, 5, 1)), archetype)

    result = performance_for(archetype)

    assert_instance_of Date, result.first_date
    assert_instance_of Date, result.last_date
    assert_equal Date.new(2025, 6, 1), result.first_date
    assert_equal Date.new(2026, 5, 1), result.last_date
  end

  # junior / senior / masters is the order players read. `group(:division)` on its own comes back
  # alphabetical — junior, masters, senior — which is why the order is asserted and not merely the
  # contents: a test on the contents alone discriminates nothing here.
  test "divisions are ordered junior, senior, masters, not alphabetically" do
    archetype = archetype_of_its_own
    event = standard_event
    2.times { record(event, archetype, division: "masters") }
    record(event, archetype, division: "junior")
    record(event, archetype, division: "senior")

    result = performance_for(archetype)

    assert_equal [ [ "Junior", 1 ], [ "Senior", 1 ], [ "Masters", 2 ] ], result.by_division
  end

  test "a division nobody played in is omitted rather than printed as zero" do
    archetype = archetype_of_its_own
    record(standard_event, archetype, division: "masters")

    assert_equal [ [ "Masters", 1 ] ], performance_for(archetype).by_division
  end

  test "placements fall into the fixed bands, and empty bands are dropped" do
    archetype = archetype_of_its_own
    event = standard_event
    [ 1, 3, 4, 9, 70 ].each { |placement| record(event, archetype, placement: placement) }
    record(event, archetype)

    result = performance_for(archetype)

    assert_equal [ [ "1st", 1 ], [ "2-4", 2 ], [ "9-16", 1 ], [ "65+", 1 ] ], result.by_placement
    assert_equal 6, result.standings_count
  end

  test "tiers are labelled from TIER_LABELS and absent tiers are dropped" do
    archetype = archetype_of_its_own
    cup = standard_event(date: Date.new(2026, 2, 10), tier: "league_cup")
    worlds = standard_event(date: Date.new(2026, 8, 20), tier: "worlds")
    record(cup, archetype)
    2.times { record(worlds, archetype) }

    result = performance_for(archetype)

    assert_equal [
      [ Tournament::TIER_LABELS.fetch("league_cup"), 1 ],
      [ Tournament::TIER_LABELS.fetch("worlds"), 2 ]
    ], result.by_tier
  end

  # `by_placement` has no band for "unknown", so its column sums to less than standings_count
  # whenever a row was recorded without a placement — and on a page whose whole point is that no
  # number quietly implies another, that gap has to be a number of its own rather than a
  # subtraction the reader is left to make.
  test "unplaced_count names the standings by_placement cannot show" do
    archetype = archetype_of_its_own
    event = standard_event
    record(event, archetype, placement: 1)
    record(event, archetype, placement: 4)
    2.times { record(event, archetype) }

    result = performance_for(archetype)

    assert_equal 4, result.standings_count
    assert_equal 2, result.placed_count
    assert_equal 2, result.unplaced_count
    assert_equal [ [ "1st", 1 ], [ "2-4", 1 ] ], result.by_placement
    assert_equal 2, result.by_placement.sum { |_band, count| count },
      "the bands must account for the placed standings and for no others"
  end

  test "best_placement is nil when no standing carries one" do
    archetype = archetype_of_its_own
    event = standard_event
    2.times { record(event, archetype) }

    result = performance_for(archetype)

    assert_equal 2, result.standings_count
    assert_nil result.best_placement
    assert_equal [], result.by_placement
  end

  # The relation this is really handed is Archetypes::MetagameScope's, which already joins
  # :tournament to filter on the pool — and every aggregate here joins it again. Rails collapses
  # two identical association joins into one, so the counts must not double; if it ever stopped,
  # COUNT(*) would silently report twice the standings.
  test "a relation that already joins the tournament is not double-counted" do
    archetype = archetype_of_its_own
    event = standard_event
    record(event, archetype, deck: field_list, placement: 1)
    record(event, archetype, placement: 8)

    scoped = TournamentStanding.where(archetype_id: archetype.id)
      .joins(:tournament)
      .where(tournaments: { standard_pool_id: standard_pools(:twm_por).id })
    result = Archetypes::Performance.call(standings: scoped)

    assert_equal [ 2, 1, 1, 1 ],
      [ result.standings_count, result.events_count, result.lists_count, result.unlisted_count ]
    assert_equal [ [ "1st", 1 ], [ "5-8", 1 ] ], result.by_placement
    assert_equal [ [ "Masters", 2 ] ], result.by_division
    assert_equal [ [ Tournament::TIER_LABELS.fetch("regional"), 2 ] ], result.by_tier
  end

  test "an archetype with no standings answers zero without raising" do
    result = performance_for(archetype_of_its_own)

    refute_predicate result, :any?
    # placed_count included: `pick` answers nil for every column on an empty relation, so each of
    # these is a `to_i` away from being nil on a page that prints it.
    assert_equal [ 0, 0, 0, 0, 0, 0 ],
      [ result.standings_count, result.events_count, result.lists_count, result.unlisted_count,
        result.placed_count, result.unplaced_count ]
    assert_nil result.best_placement
    assert_nil result.first_date
    assert_nil result.last_date
    assert_equal [ [], [], [] ], [ result.by_placement, result.by_tier, result.by_division ]
  end

  # Helpers below `private`, where a `test` declaration would never run.
  private

  SET_NAME = "PFM".freeze

  def performance_for(archetype)
    Archetypes::Performance.call(standings: TournamentStanding.where(archetype_id: archetype.id))
  end

  def archetype_of_its_own
    Archetype.create!(primary_card: trainer("Performance Marker #{next_index}"))
  end

  def trainer(name)
    Card.create!(name: name, card_type: "Trainer", set_name: SET_NAME,
                 set_number: next_index.to_s, rarity: "Uncommon", subtype: "Item")
  end

  def standard_event(date: Date.new(2026, 5, 1), tier: "regional")
    Tournament.create!(name: "Performance Event #{next_index}", date: date, format: "standard",
                       standard_pool: standard_pools(:twm_por), tier: tier,
                       created_by: users(:one))
  end

  def record(event, archetype, deck: nil, division: "masters", placement: nil)
    TournamentStanding.create!(tournament: event, archetype: archetype, deck: deck,
                               player_name: "Player #{next_index}", division: division,
                               placement: placement, created_by: users(:one))
  end

  def field_list
    Deck.create!(name: "Field list #{next_index}", user: nil, shared: true, physical: false,
                 format: "glc")
  end

  def next_index
    @next_index = @next_index.to_i + 1
  end
end
