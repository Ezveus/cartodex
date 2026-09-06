require "test_helper"

# The report's header, which is where the second grouping mode is chosen and where role mode says
# the one thing a reader cannot infer from the sections themselves.
#
# Rendered with a bare `.call`, like Archetypes::NameGroupRowTest and for the same reason — and
# that is load-bearing rather than convenient. `link_to` and the `_path` helpers resolve through a
# view_context that does not exist outside a request (see Ui::ArchetypeBadgeTest, which documents
# the trap), so the mode links are written as plain anchors over
# `Rails.application.routes.url_helpers`. A component that reached for `params` instead of the
# scope would not merely assert the wrong URL here: it would raise.
class Archetypes::CardReportTest < ActiveSupport::TestCase
  setup do
    @archetype = archetypes(:ogerpon)
    @pool = standard_pools(:twm_por)
  end

  # Iono is draw and disruption, Prime Catcher is gust and switch: half the vocabulary overlaps, so
  # the sections genuinely describe more cards between them than the sample holds. Left unsaid, a
  # reader adds the section counts and concludes the archetype plays ninety cards — the same
  # misreading the printing sub-rows already carry a sentence against.
  test "role mode says the sections overlap and do not add up to a list" do
    html = report(grouping: :role)

    assert_includes html, "archetype-overlap-note"
    assert_includes html,
      "A card is listed under every role it plays, so a card with two roles appears twice and " \
      "these sections add up to more than the 60 cards of a list."
  end

  # And type mode says nothing of the kind, because there its sections *are* a partition — a
  # warning about an overlap that does not exist would send the reader looking for one.
  test "type mode says nothing about an overlap" do
    html = report(grouping: :type)

    assert_no_match(/archetype-overlap-note/, html)
    assert_no_match(/appears twice/, html)
  end

  # The page states a mechanic for a card; a reader takes that for something somebody checked.
  # On the production data the day this shipped, every one of the 714 assignments was a rule's
  # guess and none had been confirmed, so the sections were 100% machine output under a method
  # note that said "a person decides". The count is printed rather than the provenance styled per
  # row, because what a reader needs first is whether to trust the section at all.
  test "role mode says how much of what it shows nobody has confirmed" do
    html = report(grouping: :role, proposed: 12, decided: 3)

    assert_includes html, "archetype-provenance-note"
    assert_includes html, "12 of the 15 roles below are proposals a rule made"
  end

  test "role mode says nothing about provenance once every role it shows was confirmed" do
    html = report(grouping: :role, proposed: 0, decided: 15)

    assert_no_match(/archetype-provenance-note/, html)
  end

  # Type mode's sections say nothing about what a card does, so a sentence about who decided that
  # would be answering a question the page never asked.
  test "type mode says nothing about role provenance" do
    html = report(grouping: :type, proposed: 12, decided: 0)

    assert_no_match(/archetype-provenance-note/, html)
  end

  # The heading figures print a range and a mode per section, and neither adds up: the ranges
  # belong to different lists, and the modes sum to a plausible 60-card profile that — measured on
  # the three largest production samples — no list played. The sentence renders in both modes
  # because the trap is the arithmetic, not the grouping.
  test "both modes say the section figures belong to different lists and do not add up" do
    [ :type, :role ].each do |grouping|
      html = report(grouping: grouping)

      assert_includes html, "archetype-range-note", "#{grouping} mode withheld the range note"
      assert_includes html, "a list playing none of it counts as zero here"
      assert_includes html, "adding them up across sections describes no list"
    end
  end

  # At one list there is no range to disclaim — every section prints an exact number, and adding
  # those up genuinely gives the list. The sentence would be false there, not merely redundant.
  test "one list has no range to disclaim" do
    html = report(grouping: :type, lists_count: 1)

    assert_no_match(/archetype-range-note/, html)
    assert_includes html, "there is nothing to compare it against"
  end

  test "the mode links name both groupings and mark the one the page is showing" do
    html = report(grouping: :role)

    assert_equal 2, html.scan(%r{<a [^>]*class="archetype-report-mode}).size
    assert_includes html, "group=type"
    assert_includes html, "group=role"
    # The current mode is still a link — it is a tab, and a tab you cannot click reads as
    # disabled — so what says which one is showing is aria-current, not the absence of an anchor.
    assert_match(/group=role[^"]*"[^>]*aria-current="page"/, html)
    assert_no_match(/group=type[^"]*"[^>]*aria-current="page"/, html)
  end

  # The rule this component exists to hold: a link re-emits the sample the page is *showing*,
  # which the scope answers, never the parameter that produced it. A malformed `?pool[]=junk` is
  # exactly the case where the two differ — the scope fell back to the default pool — and a link
  # built from the parameter would carry the junk back into the next request and into every copy
  # of that link. The component is handed no parameters at all, which is what makes the rule
  # structural rather than a convention.
  test "the mode links re-emit the pool the scope resolved to" do
    html = report(grouping: :type, pool: @pool)

    assert_equal 2, html.scan(/pool=#{@pool.id}\b/).size
    assert_no_match(/junk/, html)
  end

  # "All formats" is a sample too, and the value that names it is the selector's own ALL rather
  # than an omitted parameter — dropped, the link would send the reader back to the default pool
  # instead of to the blended sample they are reading.
  test "the mode links re-emit the blended sample as the selector spells it" do
    html = report(grouping: :type, pool: nil)

    assert_equal 2, html.scan(/pool=#{Archetypes::MetagameScope::ALL}\b/).size
  end

  # Nothing to regroup, nothing to choose between: both modes render the same empty state, so a
  # control here would be a click that changes the URL and not the page.
  test "an empty sample offers no mode control at all" do
    html = Archetypes::CardReport.new(stats: empty_stats, scope: scope(pool: @pool)).call

    assert_includes html, "No decklist recorded for this sample yet."
    assert_no_match(/archetype-report-mode/, html)
  end

  private

  def report(grouping:, pool: nil, proposed: 0, decided: 0, lists_count: 4)
    Archetypes::CardReport.new(
      stats: stats(grouping, proposed: proposed, decided: decided, lists_count: lists_count),
      scope: scope(pool: pool)
    ).call
  end

  # One card in one section, which is all the header needs — what this file asks about is the
  # header, and Archetypes::CardStatsTest owns the grouping itself.
  def stats(grouping, proposed: 0, decided: 0, lists_count: 4)
    entry = Archetypes::CardStats::Entry.new(
      card: Card.new(name: "Iono", set_name: "PAL", set_number: "185"),
      fingerprint: "PAL-185", inclusion_count: 4, inclusion_pct: 100.0,
      min_copies: 4, max_copies: 4, modes: [ 4 ], core: true
    )
    group = Archetypes::CardStats::NameGroup.new(
      name: "Iono", inclusion_count: 4, inclusion_pct: 100.0, entries: [ entry ]
    )
    category = Archetypes::CardStats::CategoryGroup.new(
      key: grouping == :role ? :draw : :supporter,
      label: grouping == :role ? "Draw" : "Supporter", name_groups: [ group ],
      copies_per_list: Array.new(lists_count, 4)
    )

    Archetypes::CardStats::Result.new(
      lists_count: lists_count, categories: [ category ], fixed_core_cards: 1,
      fixed_core_copies: 4, grouping: grouping, proposed_roles: proposed, decided_roles: decided
    )
  end

  def empty_stats
    Archetypes::CardStats::Result.new(
      lists_count: 0, categories: [], fixed_core_cards: 0, fixed_core_copies: 0, grouping: :type
    )
  end

  # `pool: nil` is the blended sample: MetagameScope::Result#all_formats? is `pool.nil?`.
  def scope(pool:)
    Archetypes::MetagameScope::Result.new(
      archetype: @archetype, standings: nil, listed_standings: nil, pool: pool, options: [],
      lists_count: 4, online_lists_count: 0, unpooled: false
    )
  end
end
