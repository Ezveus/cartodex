require "test_helper"

# The archetype index lists archetypes nobody has recorded a result for — they are the majority,
# because members tag their own decks with them — so a caller must never have to tell "no
# standings" from "absent from the Hash". And the whole page costs one query whatever it lists.
#
# The sample is built per test, never fixtured.
class Archetypes::IndexCountsTest < ActiveSupport::TestCase
  test "answers with an entry for every id asked about, zero included" do
    recorded = archetype_of_its_own
    silent = archetype_of_its_own
    record(standard_event, recorded, deck: field_list)

    counts = Archetypes::IndexCounts.call(archetype_ids: [ recorded.id, silent.id ])

    assert_equal [ recorded.id, silent.id ], counts.keys
    assert_equal [ 1, 1, 1 ],
      [ counts[recorded.id].standings, counts[recorded.id].events, counts[recorded.id].lists ]
    assert_equal [ 0, 0, 0 ],
      [ counts[silent.id].standings, counts[silent.id].events, counts[silent.id].lists ]
    assert_nil counts[silent.id].last_event_on
  end

  test "events are a distinct count of tournaments while lists count only the standings carrying one" do
    archetype = archetype_of_its_own
    event = standard_event(date: Date.new(2026, 5, 1))
    other_event = standard_event(date: Date.new(2025, 6, 1))
    record(event, archetype, deck: field_list)
    record(event, archetype)
    record(other_event, archetype, deck: field_list)

    counts = Archetypes::IndexCounts.call(archetype_ids: [ archetype.id ]).fetch(archetype.id)

    assert_equal 3, counts.standings
    assert_equal 2, counts.events
    assert_equal 2, counts.lists
  end

  # MAX() over a date column comes back as a String from SQLite: the aggregate carries no column
  # type for Rails to cast from, so the conversion has to happen in the service.
  test "last_event_on is the most recent event's date, as a Date" do
    archetype = archetype_of_its_own
    record(standard_event(date: Date.new(2025, 6, 1)), archetype)
    record(standard_event(date: Date.new(2026, 5, 1)), archetype)
    record(standard_event(date: Date.new(2026, 1, 3)), archetype)

    counts = Archetypes::IndexCounts.call(archetype_ids: [ archetype.id ]).fetch(archetype.id)

    assert_instance_of Date, counts.last_event_on
    assert_equal Date.new(2026, 5, 1), counts.last_event_on
  end

  test "an empty id list answers with an empty Hash and costs no query" do
    result = nil
    queries = count_queries { result = Archetypes::IndexCounts.call(archetype_ids: []) }

    assert_equal({}, result)
    assert_equal 0, queries
  end

  test "a repeated id is asked about once and answered once" do
    archetype = archetype_of_its_own
    record(standard_event, archetype)

    counts = Archetypes::IndexCounts.call(archetype_ids: [ archetype.id, archetype.id ])

    assert_equal [ archetype.id ], counts.keys
    assert_equal 1, counts.fetch(archetype.id).standings
  end

  # Flat cost: the index renders a page of rows and must not pay per row.
  test "costs one query whatever the number of archetypes" do
    one = archetype_of_its_own
    record(standard_event, one, deck: field_list)

    many = Array.new(4) do
      archetype_of_its_own.tap { |archetype| record(standard_event, archetype, deck: field_list) }
    end

    small = count_queries { Archetypes::IndexCounts.call(archetype_ids: [ one.id ]) }
    large = count_queries { Archetypes::IndexCounts.call(archetype_ids: many.map(&:id)) }

    assert_equal 1, small
    assert_equal small, large
  end

  # Helpers below `private`, where a `test` declaration would never run.
  private

  SET_NAME = "IDX".freeze

  def archetype_of_its_own
    Archetype.create!(primary_card: trainer("Index Marker #{next_index}"))
  end

  def trainer(name)
    Card.create!(name: name, card_type: "Trainer", set_name: SET_NAME,
                 set_number: next_index.to_s, rarity: "Uncommon", subtype: "Item")
  end

  def standard_event(date: Date.new(2026, 5, 1))
    Tournament.create!(name: "Index Event #{next_index}", date: date, format: "standard",
                       standard_pool: standard_pools(:twm_por), tier: "regional",
                       created_by: users(:one))
  end

  def record(event, archetype, deck: nil)
    TournamentStanding.create!(tournament: event, archetype: archetype, deck: deck,
                               player_name: "Player #{next_index}", division: "masters",
                               created_by: users(:one))
  end

  def field_list
    Deck.create!(name: "Field list #{next_index}", user: nil, shared: true, physical: false,
                 format: "glc")
  end

  def next_index
    @next_index = @next_index.to_i + 1
  end
end
