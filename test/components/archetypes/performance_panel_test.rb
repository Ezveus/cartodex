require "test_helper"

# The panel exists to stop one number implying another, so its tests are about the sentences that
# say what a number does *not* cover — and about the two breakdowns that used to carry a message
# nothing could print.
#
# Rendered through ApplicationController.renderer rather than with a bare `.call`: the panel calls
# `localize`, which Phlex::Rails resolves through a view_context that does not exist outside a
# request.
class Archetypes::PerformancePanelTest < ActiveSupport::TestCase
  # Ui::Stat prints the label it is handed, so agreement is this panel's job. One standing at one
  # event with one list is the shape of a freshly imported archetype, not a corner case.
  test "puts its counter labels in the singular at one" do
    html = panel(standings_count: 1, events_count: 1, lists_count: 1, placed_count: 1)

    assert_includes html, %(<span class="stat-label">standing</span>)
    assert_includes html, %(<span class="stat-label">event</span>)
    assert_includes html, %(<span class="stat-label">list</span>)
    assert_no_match(/>standings</, html)
  end

  test "puts them back in the plural past one" do
    html = panel(standings_count: 4, events_count: 2, lists_count: 3, placed_count: 4)

    assert_includes html, %(<span class="stat-label">standings</span>)
    assert_includes html, %(<span class="stat-label">events</span>)
    assert_includes html, %(<span class="stat-label">lists</span>)
  end

  # `placement` is nullable and there is no band for "unknown", so the By placement column sums to
  # less than the standings count above it. Unnamed, that gap reads as a bug in the table.
  test "names the standings the placement column cannot hold" do
    html = panel(standings_count: 5, events_count: 2, lists_count: 5, placed_count: 3,
                 by_placement: [ [ "1st", 1 ], [ "9-16", 2 ] ])

    assert_includes html, "2 of these standings carry no placement, so they are not counted in this column."
  end

  test "says it in the singular for one such standing" do
    html = panel(standings_count: 5, events_count: 2, lists_count: 5, placed_count: 4,
                 by_placement: [ [ "1st", 4 ] ])

    assert_includes html, "1 of these standings carries no placement, so it is not counted in this column."
  end

  test "says nothing about it when every standing carries a placement" do
    html = panel(standings_count: 4, events_count: 2, lists_count: 4, placed_count: 4,
                 by_placement: [ [ "1st", 4 ] ])

    assert_no_match(/carry no placement|carries no placement/, html)
  end

  # The one breakdown that can legitimately come back empty on well-formed data.
  test "explains an empty placement column instead of showing a heading over nothing" do
    html = panel(standings_count: 2, events_count: 1, lists_count: 2, placed_count: 0,
                 by_placement: [])

    assert_includes html, "No placement recorded on these standings."
    # The empty state already says it; the note would restate the same fact with a number.
    assert_no_match(/carry no placement/, html)
  end

  # `tier` and `division` are NOT NULL behind validated enums whose whole key list the service
  # filter_maps over, so these two are non-empty whenever the panel renders at all. The messages
  # that used to sit here claimed an absence the schema forbids.
  test "carries no unreachable empty message for tier or division" do
    html = panel(standings_count: 2, events_count: 1, lists_count: 2, placed_count: 2)

    assert_no_match(/No tier recorded/, html)
    assert_no_match(/No age division recorded/, html)
    assert_includes html, "<h3>By tier</h3>"
    assert_includes html, "<h3>By division</h3>"
  end

  # And a breakdown that somehow arrives empty — only a write bypassing the enum can produce one —
  # is not drawn, rather than leaving a heading standing over nothing.
  test "omits a breakdown that has no rows at all" do
    html = panel(standings_count: 2, events_count: 1, lists_count: 2, placed_count: 2,
                 by_tier: [], by_division: [])

    assert_no_match(/By tier/, html)
    assert_no_match(/By division/, html)
    assert_includes html, "<h3>By placement</h3>"
  end

  # The panel counts every standing; the card report below it counts only the listed ones. The gap
  # is named for the same reason the placement gap is.
  test "names the standings with no decklist, agreeing with itself in the singular" do
    html = panel(standings_count: 2, events_count: 1, lists_count: 1, placed_count: 2)

    assert_includes html, "1 of these standings carries no decklist, so the card report below " \
                          "speaks for the 1 list that does."
  end

  test "names them in the plural" do
    html = panel(standings_count: 5, events_count: 1, lists_count: 3, placed_count: 5)

    assert_includes html, "2 of these standings carry no decklist, so the card report below " \
                          "speaks for the 3 lists that do."
  end

  private

  def panel(standings_count:, events_count:, lists_count:, placed_count:,
            by_placement: [ [ "1st", 1 ] ], by_tier: [ [ "Regional / Special Championship", 1 ] ],
            by_division: [ [ "Masters", 1 ] ])
    performance = Archetypes::Performance::Result.new(
      standings_count: standings_count, events_count: events_count, lists_count: lists_count,
      placed_count: placed_count, first_date: Date.new(2026, 8, 28), last_date: Date.new(2026, 8, 28),
      best_placement: 1, by_placement: by_placement, by_tier: by_tier, by_division: by_division
    )

    ApplicationController.renderer.render(
      Archetypes::PerformancePanel.new(performance: performance), layout: false
    )
  end
end
