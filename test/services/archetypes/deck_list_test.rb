require "test_helper"

# Every deck here is built per test and tagged with an archetype of its own, so fixture decks
# can never satisfy an assertion by accident — and the two columns that decide membership are
# always set to *different* archetypes wherever they could disagree, since agreement is the case
# that cannot tell the two rules apart.
class Archetypes::DeckListTest < ActiveSupport::TestCase
  test "a field list belongs to its standing's archetype, never to its own tag" do
    listed_as, tagged_as = archetype_of_its_own, archetype_of_its_own
    deck = field_list(archetype: tagged_as)
    record(event, listed_as, deck: deck)

    assert_equal [ deck.id ], ids(listed_as)
    assert_empty ids(tagged_as)
  end

  test "a member's shared deck belongs to its own tag" do
    archetype = archetype_of_its_own
    deck = member_deck(users(:two), archetype, shared: true)

    assert_equal [ deck.id ], ids(archetype)
  end

  test "a member's private deck is never public, to a visitor or to another member" do
    archetype = archetype_of_its_own
    member_deck(users(:two), archetype, shared: false)

    assert_empty ids(archetype)
    assert_empty ids(archetype, viewer: users(:one))
  end

  # The trap `where.not(user_id: viewer)` sets: `NULL != ?` is NULL, so that spelling empties the
  # field lists for every signed-in reader while still hiding their own deck.
  test "the reader's own decks leave the public list and the field lists stay" do
    archetype = archetype_of_its_own
    field = field_list
    record(event, archetype, deck: field)
    member_deck(users(:one), archetype, shared: true)

    result = list(archetype, viewer: users(:one))

    assert_equal [ field.id ], result.decks.map(&:id)
    assert_equal 1, result.total
  end

  test "a deck two standings point at is listed and counted once" do
    archetype = archetype_of_its_own
    deck = field_list
    record(event, archetype, deck: deck)
    record(event, archetype, deck: deck)

    result = list(archetype)

    assert_equal [ deck.id ], result.decks.map(&:id)
    assert_equal 1, result.total

    24.times { record(event, archetype, deck: field_list) }
    result = list(archetype, page: 2)

    assert_equal 25, result.total
    assert_equal 2, result.pages
    assert_equal 1, result.decks.size
  end

  test "orders by event date, then placement with none last, then newest deck" do
    archetype = archetype_of_its_own
    day = Date.new(2026, 5, 1)
    same_day = event(date: day)
    third = field_list.tap { |d| record(same_day, archetype, deck: d, placement: 3) }
    unplaced = field_list.tap { |d| record(same_day, archetype, deck: d) }
    first = field_list.tap { |d| record(same_day, archetype, deck: d, placement: 1) }
    tied_old = field_list.tap { |d| record(same_day, archetype, deck: d, placement: 5) }
    tied_new = field_list.tap { |d| record(same_day, archetype, deck: d, placement: 5) }
    older = field_list.tap { |d| record(event(date: day - 30), archetype, deck: d, placement: 1) }
    newer = field_list.tap { |d| record(event(date: day + 30), archetype, deck: d, placement: 9) }
    # No standing: it sorts at the day it was created — behind that day's placed lists, since it
    # carries no placement, and ahead of the unplaced one, being the newer deck. An afternoon
    # timestamp on the same day is what catches a missing `date(…)` around `created_at`.
    member = member_deck(users(:two), archetype, shared: true)
    member.update_column(:created_at, day.to_time.change(hour: 15))

    assert_equal [ newer, first, third, tied_new, tied_old, member, unplaced, older ].map(&:id),
                 ids(archetype)
  end

  test "the reader's own decks are private and shared alike, ordered by name, and only this archetype's" do
    archetype, other = archetype_of_its_own, archetype_of_its_own
    zeta = member_deck(users(:one), archetype, shared: false, name: "Zeta")
    alpha = member_deck(users(:one), archetype, shared: true, name: "Alpha")
    member_deck(users(:one), other, shared: true, name: "Beta")

    assert_equal [ alpha.id, zeta.id ], list(archetype, viewer: users(:one)).own_decks.map(&:id)
    assert_empty list(archetype, viewer: users(:two)).own_decks
    assert_empty list(archetype).own_decks
  end

  test "a page past the end renders the last page, and a page below one the first" do
    archetype = archetype_of_its_own
    25.times { record(event, archetype, deck: field_list) }

    assert_equal 2, list(archetype, page: 99).page
    assert_equal 1, list(archetype, page: 99).decks.size
    assert_equal 1, list(archetype, page: -3).page
    assert_equal 1, list(archetype_of_its_own, page: 5).page
  end

  test "a field list is captioned with its event, placement and division" do
    archetype = archetype_of_its_own
    named = event(name: "EUIC 2026")
    { 1 => "1st", 2 => "2nd", 3 => "3rd", 11 => "11th", 21 => "21st" }.each do |placement, ordinal|
      deck = field_list
      record(named, archetype, deck: deck, placement: placement)

      assert_equal "EUIC 2026 — #{ordinal} · Masters", caption(archetype, deck)
    end

    unplaced = field_list
    record(named, archetype, deck: unplaced, division: "open")
    assert_equal "EUIC 2026 · Open", caption(archetype, unplaced)

    assert_nil caption(archetype, member_deck(users(:two), archetype, shared: true))
  end

  # A deck two standings point at is listed for the ones filed under this archetype, so it is
  # sorted and captioned by those alone — and by one row of them, never a date from one and a
  # placement from another.
  test "a deck in two standings is sorted and captioned by this archetype's one" do
    listed_as, elsewhere = archetype_of_its_own, archetype_of_its_own
    shared = field_list
    record(event(name: "Older Event", date: Date.new(2026, 1, 1)), listed_as, deck: shared, placement: 40)
    record(event(name: "Newer Event", date: Date.new(2026, 6, 1)), elsewhere, deck: shared, placement: 1)
    between = field_list.tap { |d| record(event(date: Date.new(2026, 3, 1)), listed_as, deck: d, placement: 5) }

    assert_equal [ between.id, shared.id ], ids(listed_as)
    assert_equal "Older Event — 40th · Masters", caption(listed_as, shared)
    assert_equal "Newer Event — 1st · Masters", caption(elsewhere, shared)
  end

  test "among one archetype's standings of a deck, the latest event wins, then the best placement" do
    archetype = archetype_of_its_own
    deck = field_list
    record(event(name: "Early", date: Date.new(2026, 1, 1)), archetype, deck: deck, placement: 1)
    late = event(name: "Late", date: Date.new(2026, 6, 1))
    record(late, archetype, deck: deck, placement: 30)
    record(late, archetype, deck: deck, placement: 7)
    # The deck sorts as June, 7th — its latest event, and its best placement *there*. A June 3rd
    # therefore goes ahead of it; MAX(date) beside MIN(placement) would read it as June, 1st (the
    # 1st is January's) and put it first.
    june_third = field_list.tap { |d| record(late, archetype, deck: d, placement: 3) }
    march = field_list.tap { |d| record(event(date: Date.new(2026, 3, 1)), archetype, deck: d, placement: 2) }

    assert_equal [ june_third.id, deck.id, march.id ], ids(archetype)
    assert_equal "Late — 7th · Masters", caption(archetype, deck)
  end

  private

  def list(archetype, viewer: nil, page: 1)
    Archetypes::DeckList.call(archetype: archetype, viewer: viewer, page: page)
  end

  def caption(archetype, deck)
    list(archetype).caption_for(deck)
  end

  def ids(archetype, viewer: nil)
    list(archetype, viewer: viewer).decks.map(&:id)
  end

  def archetype_of_its_own
    Archetype.create!(primary_card: Card.create!(name: "Deck List Marker #{next_index}", card_type: "Trainer",
                                                 set_name: "DLT", set_number: next_index.to_s,
                                                 rarity: "Uncommon", subtype: "Item"))
  end

  def event(date: Date.new(2026, 5, 1), name: "Deck List Event #{next_index}")
    Tournament.create!(name: name, date: date, format: "standard", standard_pool: standard_pools(:twm_por),
                       tier: "regional", created_by: users(:one))
  end

  def record(event, archetype, deck: nil, division: "masters", placement: nil)
    TournamentStanding.create!(tournament: event, archetype: archetype, deck: deck,
                               player_name: "Player #{next_index}", division: division,
                               placement: placement, created_by: users(:one))
  end

  def field_list(archetype: nil)
    Deck.create!(name: "Field list #{next_index}", user: nil, shared: true, physical: false,
                 format: "glc", archetype: archetype)
  end

  def member_deck(user, archetype, shared:, name: "Member deck #{next_index}")
    Deck.create!(name: name, user: user, shared: shared, physical: false, format: "glc", archetype: archetype)
  end

  def next_index
    @next_index = @next_index.to_i + 1
  end
end
