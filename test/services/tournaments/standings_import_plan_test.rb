require "test_helper"

class Tournaments::StandingsImportPlanTest < ActiveSupport::TestCase
  # tournaments(:one) is "Regional Championship" on 2026-03-14 with standings for Ash Ketchum
  # (masters, no field list) and Giovanni (masters, no field list).
  EXISTING = { event_name: "Regional Championship", event_date: Date.new(2026, 3, 14) }.freeze

  test "groups rows into one event per name and date, newest first" do
    plan = plan_for([
      row(event_name: "World Championships 2026", event_date: Date.new(2026, 8, 28)),
      row(event_name: "NAIC 2026, New Orleans", event_date: Date.new(2026, 6, 10), player_name: "A"),
      row(event_name: "NAIC 2026, New Orleans", event_date: Date.new(2026, 6, 10), player_name: "B", division: "junior")
    ])

    assert_equal [ "World Championships 2026", "NAIC 2026, New Orleans" ], plan.events.map(&:name)
    # The Masters and Junior halves of one event are one EventPlan: they arrive as separate
    # Limitless headings and must not become separate rows of a public catalog.
    assert_equal 2, plan.events.second.rows.size
  end

  # tournaments.tier defaults to "regional" in the schema, so an undecided tier files a World
  # Championship as a Regional — which then hands a claimant 350 championship points from
  # Tournament::CP_REFERENCE instead of 600, on a page only its creator or an admin can fix.
  test "derives the tier from the event name" do
    names = {
      "World Championships 2026" => "worlds",
      "NAIC 2026, New Orleans" => "international",
      "Regional Indianapolis, IN" => "regional",
      "Special Event Turin" => "regional",
      "Champions League Aichi" => "other"
    }

    names.each do |name, tier|
      event = plan_for([ row(event_name: name) ]).events.first
      assert_equal tier, event.tier, "#{name.inspect} should be #{tier}"
    end
  end

  # "standard-jp" is the Japanese card pool. Writing it as "standard" would force a western
  # StandardPool onto a Japanese event — the same lie a missing pool is refused for, in the other
  # direction — so it becomes `other` with a name, which needs no pool and is true.
  test "records a Japanese format as other rather than anchoring it to a western pool" do
    event = plan_for([ row(event_name: "Champions League Aichi", format: "standard-jp") ]).events.first

    assert_equal "other", event.format
    assert_equal "Standard (JP)", event.other_format_name
    assert_nil event.standard_pool
    assert_not event.blocked?
  end

  test "blocks a format cartodex has no value for" do
    event = plan_for([ row(format: "unlimited") ]).events.first

    assert event.blocked?
    assert_match(/unlimited/, event.blocked_reason)
    assert_equal [ :blocked ], event.rows.map(&:status).uniq
  end

  # Tournament requires a standard_pool when the format is standard, and StandardPool.at is nil
  # for any date before the earliest pool's legal_on. Inventing one, or quietly downgrading the
  # format, would both write a lie into a public catalog — so the event is refused with a reason
  # the admin can act on.
  test "blocks a Standard event no pool covers, and says which date" do
    event = plan_for([ row(event_date: Date.new(2024, 11, 2), event_name: "Regional Antwerp") ]).events.first

    assert event.blocked?
    assert_match(/2024-11-02/, event.blocked_reason)
  end

  test "reuses an existing event's own classification instead of re-deriving it" do
    event = plan_for([ row(**EXISTING) ]).events.first

    assert_equal tournaments(:one), event.tournament
    assert_equal tournaments(:one).tier, event.tier
    assert_equal standard_pools(:twm_por), event.standard_pool
    assert_empty event.similar_tournaments
  end

  # A hand-typed row naming an archetype and no list is the common case, and deck_id is NULL on
  # it. Filling that overwrites nothing — while skipping it would make the two runs an admin
  # actually makes (re-importing once Limitless posts the lists, enriching rows a member typed) do
  # nothing at all.
  test "enriches an existing standing that has no field list" do
    row_plan = plan_for([ row(**EXISTING, player_name: "Ash Ketchum") ]).events.first.rows.first

    assert_equal :enrich, row_plan.status
    assert_equal tournament_standings(:ash_masters), row_plan.standing
  end

  test "skips an existing standing when there is no list to add" do
    row_plan = plan_for([ row(**EXISTING, player_name: "Ash Ketchum", list_url: nil) ]).events.first.rows.first

    assert_equal :skip, row_plan.status
    assert_match(/no field list/, row_plan.reason)
  end

  # The UNIQUE key is (event, player, division), so a row a member typed under the form's Masters
  # default and the Senior row this import derives from a /SR suffix collide on nothing and both go
  # public — the same human, twice. Which of the two is right is a fact about a person, so the plan
  # flags it rather than resolving it.
  test "flags a player already recorded at the event in another division" do
    row_plan = plan_for([ row(**EXISTING, player_name: "Ash Ketchum", division: "senior") ]).events.first.rows.first

    assert_equal :create, row_plan.status
    assert_equal tournament_standings(:ash_masters), row_plan.other_division
  end

  test "blocks a row whose division suffix means nothing here" do
    row_plan = plan_for([ row(division: nil, division_suffix: "XX") ]).events.first.rows.first

    assert_equal :blocked, row_plan.status
    assert_match(/"XX"/, row_plan.reason)
  end

  # Per event *and* division: a cap applied across the whole event keeps ten Masters rows and drops
  # the single Junior one, which is the row hardest to find anywhere else.
  test "caps the best placements per division, not per event" do
    rows = [
      row(player_name: "M1", placement: 1), row(player_name: "M2", placement: 2),
      row(player_name: "M3", placement: 3),
      row(player_name: "J1", placement: 40, division: "junior")
    ]

    kept = plan_for(rows, limit_per_event: 2).events.first.rows.map { |r| r.row.player_name }

    assert_equal %w[M1 M2 J1], kept
  end

  test "keeps only the events whose name matches a filter" do
    rows = [ row(event_name: "World Championships 2026"), row(event_name: "Regional Indianapolis, IN") ]

    plan = plan_for(rows, event_filters: [ "world championships" ])

    assert_equal [ "World Championships 2026" ], plan.events.map(&:name)
  end

  test "reports a plan over the ceiling instead of importing it" do
    rows = [ row(player_name: "A"), row(player_name: "B") ]

    assert plan_for(rows, max_rows: 1).over_limit?
    assert_not plan_for(rows, max_rows: 2).over_limit?
  end

  # Limitless records the day an event starts, and a member cataloguing a three-day International
  # may well have typed the day they played, under a slightly different name. That duplicate is
  # invisible to the UNIQUE key on (name_normalized, date) and becomes undeletable the moment
  # anybody records a participation at it.
  test "warns about a near-identical event on a neighbouring date" do
    event = plan_for([ row(event_name: "Regional Championship 2026", event_date: Date.new(2026, 3, 15)) ]).events.first

    assert_nil event.tournament
    assert_equal [ tournaments(:one) ], event.similar_tournaments
  end

  private

  def row(**overrides)
    Tournaments::LimitlessResults::Row.new(
      **{
        event_name: "World Championships 2026", event_date: Date.new(2026, 8, 28),
        division: "masters", division_suffix: nil, format: "standard",
        player_name: "Tomi Markkula", placement: 4,
        list_url: "https://limitlesstcg.com/decks/list/28788"
      }.merge(overrides)
    )
  end

  def plan_for(rows, **options)
    Tournaments::StandingsImportPlan.call(rows: rows, **options)
  end
end
