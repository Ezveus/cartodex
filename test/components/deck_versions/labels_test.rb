require "test_helper"

# The one helper every version-listing surface prints a period through. Built on stand-ins rather
# than records: what is under test is the wording, and a period is whatever
# `Decks::VersionPeriods` hands over, which these structs mirror field for field.
class DeckVersions::LabelsTest < ActiveSupport::TestCase
  Period = Struct.new(:first_on, :last_on, :results, :entries)
  Version = Struct.new(:label, :format_label)

  def version = Version.new("v2", "Standard (TEF-PBL)")

  test "a span within one month writes the month and the year once" do
    period = Period.new(Date.new(2026, 9, 17), Date.new(2026, 9, 22), 5, 0)

    assert_equal "played Sep 17 → 22, 2026 · 5 matches", DeckVersions::Labels.played(period)
  end

  test "a single day is one date, and one match is singular" do
    period = Period.new(Date.new(2026, 9, 22), Date.new(2026, 9, 22), 1, 0)

    assert_equal "played Sep 22, 2026 · 1 match", DeckVersions::Labels.played(period)
  end

  test "a span across months or years names what differs" do
    assert_equal "played Sep 28 → Oct 3, 2026 · 2 matches",
      DeckVersions::Labels.played(Period.new(Date.new(2026, 9, 28), Date.new(2026, 10, 3), 2, 0))
    assert_equal "played Dec 28, 2025 → Jan 3, 2026 · 2 matches",
      DeckVersions::Labels.played(Period.new(Date.new(2025, 12, 28), Date.new(2026, 1, 3), 2, 0))
  end

  # A participation dates the version without being a match, so it cannot be counted as one.
  # Counted matches with no date are said as such, never as "not played yet".
  test "matches with no date are counted and said to be undated" do
    assert_equal "1 match · date unknown", DeckVersions::Labels.played(Period.new(nil, nil, 1, 0))
    assert_equal "3 matches · date unknown", DeckVersions::Labels.played(Period.new(nil, nil, 3, 0))
    assert_equal "v2 — Standard (TEF-PBL) · date unknown", DeckVersions::Labels.option(version, Period.new(nil, nil, 3, 0))
  end

  test "a version played only at an event carries its dates and no match count" do
    period = Period.new(Date.new(2026, 9, 20), Date.new(2026, 9, 20), 0, 1)

    assert_equal "played Sep 20, 2026", DeckVersions::Labels.played(period)
  end

  test "nothing filed, or no period at all, is not played yet" do
    assert_equal "not played yet", DeckVersions::Labels.played(Period.new(nil, nil, 0, 0))
    assert_equal "not played yet", DeckVersions::Labels.played(nil)
  end

  test "an option carries the span without its year or count" do
    period = Period.new(Date.new(2026, 9, 17), Date.new(2026, 9, 22), 5, 1)

    assert_equal "v2 — Standard (TEF-PBL) · played Sep 17 → 22", DeckVersions::Labels.option(version, period)
    assert_equal "v2 — Standard (TEF-PBL) · not played yet", DeckVersions::Labels.option(version, nil)
  end
end
