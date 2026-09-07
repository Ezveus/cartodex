require "test_helper"

# Four independent predicates decide what this component draws, and each of them was, until this
# file existed, only ever exercised in the one combination the production data happens to hold.
# Every test below pins one of them against a scope built by hand.
#
# Rendered through ApplicationController.renderer: the form's action is `archetype_path`, which
# Phlex::Rails resolves through a view_context.
class Archetypes::SampleSelectorTest < ActiveSupport::TestCase
  ALL = Archetypes::MetagameScope::ALL

  # An archetype whose every standing sits in one pool gets two labels over one sample —
  # "TEF-PBL — 1 list" and "All formats — 1 list" — which is a filter that cannot filter. Measured
  # on the production data this is archetype 47, and it is the majority case.
  test "draws no select when every option describes the same sample" do
    html = selector(lists_count: 1, options: [ pool_option("9", 1), all_option(1) ])

    assert_no_match(/<select/, html)
    assert_no_match(/Events outside Standard/, html)
  end

  test "draws the select once two pools genuinely differ" do
    html = selector(lists_count: 3, options: [ pool_option("9", 3), pool_option("8", 22), all_option(25) ])

    assert_includes html, %(<select name="pool")
    assert_includes html, %(<option value="9" selected>)
  end

  # The note explains a distinction — a list counted under "All formats" and under no pool — that
  # exists only when a standing sits on an event with no Standard pool. Printed otherwise it sends
  # the reader hunting for rows the sample does not hold; measured on archetype 6, which has no
  # such event, it was printed anyway.
  test "explains the unpooled lists only when there are some" do
    without = selector(lists_count: 3, options: [ pool_option("9", 3), pool_option("8", 22), all_option(25) ])
    with = selector(lists_count: 3, unpooled: true,
                    options: [ pool_option("9", 3), all_option(5) ])

    assert_no_match(/Events outside Standard carry no pool/, without)
    assert_includes with, "Events outside Standard carry no pool, so their lists are counted " \
                          "under “All formats” only."
  end

  # A single pool plus a non-Standard event is a real choice even though only one pool option
  # exists, so `unpooled?` is what makes it selectable at all.
  test "an unpooled sample is selectable on its own" do
    html = selector(lists_count: 3, unpooled: true, options: [ pool_option("9", 3), all_option(5) ])

    assert_includes html, %(<select name="pool")
  end

  # The clause promises a fuller sample one click away, so it is printed only when one exists.
  test "offers a fuller sample only when an option actually holds more lists" do
    html = selector(lists_count: 3, options: [ pool_option("9", 3), pool_option("8", 22), all_option(25) ])

    assert_includes html, "supports no conclusion about the archetype — a fuller sample may be " \
                          "one click away above."
  end

  # Selectable, small, and already on the largest sample: a GLC-only archetype reading "All
  # formats" was told to click above for more of the same.
  test "stops at a full stop when this is already the largest sample" do
    html = selector(lists_count: 3, pool: nil, unpooled: true,
                    options: [ pool_option("9", 2), all_option(3) ])

    assert_includes html, "supports no conclusion about the archetype."
    assert_no_match(/one click away/, html)
  end

  # Nothing to say at all: a big enough sample with no genuine choice renders no wrapper, or the
  # empty flex block would still take its margin above the panel below it.
  test "renders nothing when there is neither a choice nor a warning" do
    html = selector(lists_count: 40, options: [ pool_option("9", 40), all_option(40) ])

    assert_no_match(/archetype-sample/, html)
  end

  # The blend the selector itself cannot separate: a pool is the only axis it offers, and an online
  # weekly anchored to TEF-PBL sits in the same bucket as a Regional anchored to TEF-PBL. Said
  # above the card report because the card report's denominator is lists.
  test "names how much of the sample comes from online play" do
    html = selector(lists_count: 16, online_lists_count: 13,
                    options: [ pool_option("9", 16), pool_option("8", 22), all_option(38) ])

    assert_includes html, "13 of these 16 lists come from an online tournament. The card report " \
                          "below counts online and paper lists together."
  end

  test "says it in the singular for one such list" do
    html = selector(lists_count: 4, online_lists_count: 1,
                    options: [ pool_option("9", 4), pool_option("8", 22), all_option(26) ])

    assert_includes html, "1 of these 4 lists comes from an online tournament."
  end

  # "16 of these 16 lists" is a strange way to say "all of them", and one online import produces
  # exactly that sample.
  test "says every list rather than counting them all out when the sample is all online" do
    html = selector(lists_count: 16, online_lists_count: 16,
                    options: [ pool_option("9", 16), pool_option("8", 22), all_option(38) ])

    assert_includes html, "Every list in this sample comes from an online tournament."
    assert_no_match(/16 of these 16/, html)
    # The second sentence claims the report counts both kinds, which is false here — and was
    # printed unconditionally until #160. Measured on the production data, 23 of the 48 archetypes
    # carrying a list open on exactly this sample, so 23 pages said it. Both assertions are
    # needed: without the one above, an implementation that drops the whole note also passes.
    assert_no_match(/counts online and paper lists together/, html)
  end

  # No "0 online lists" line on an archetype nobody has imported an online result for: a sentence
  # about an absence reads as a warning about nothing.
  test "says nothing about online play when the sample holds none" do
    html = selector(lists_count: 3, options: [ pool_option("9", 3), pool_option("8", 22), all_option(25) ])

    assert_no_match(/online/, html)
  end

  # The reason `online_lists?` had to join the guard rather than ride on the other two: a sample of
  # sixteen lists all sitting in one pool is neither selectable nor small, so the wrapper this note
  # lives in was not drawn at all — which is exactly the shape one online import produces.
  test "draws the wrapper for the online note even with no choice and no small sample" do
    html = selector(lists_count: 40, online_lists_count: 40,
                    options: [ pool_option("9", 40), all_option(40) ])

    assert_includes html, "archetype-sample"
    assert_no_match(/<select/, html)
    assert_no_match(/Small sample/, html)
    assert_includes html, "Every list in this sample comes from an online tournament."
  end

  # The two controls on this page each replace the whole query string, so each has to carry what
  # the other chose. The mode links re-emit the pool; without this the sample form dropped the
  # grouping, and a reader comparing one archetype's roles across two pools was thrown back into
  # type mode on every switch, silently.
  test "the sample form carries the grouping the page is showing" do
    html = selector(lists_count: 12, options: [ pool_option(9, 12), pool_option(8, 4) ],
                    grouping: :role)

    assert_match(/<input[^>]*name="group"[^>]*value="role"/, html)
  end

  test "the sample form says nothing about grouping in the report's default mode" do
    html = selector(lists_count: 12, options: [ pool_option(9, 12), pool_option(8, 4) ])

    assert_no_match(/name="group"/, html)
  end

  # ---- the venue axis (#160) ----

  # One pool and both venues, which is 15 of the 24 blended archetypes in production. Two
  # assertions and not one: the first catches a form guard written as `&&`, which drops the form
  # entirely here, and the second catches a Sample select widened to that guard, which renders a
  # `<select name="pool">` of one option — the non-choice `selectable?` exists to prevent.
  test "one pool and two venues renders the venue select alone" do
    html = selector(lists_count: 28, online_lists_count: 20, venue_selectable: true,
                    options: [ pool_option("9", 28), all_option(28) ])

    assert_match(/<select name="venue"/, html)
    assert_no_match(/<select name="pool"/, html)
    assert_includes html, "Venue"
  end

  # Two pools and both venues: the only shape where both render, and the state the system test
  # measures the geometry of.
  test "two pools and two venues renders both selects" do
    html = selector(lists_count: 28, online_lists_count: 20, venue_selectable: true,
                    options: [ pool_option("9", 28), pool_option("8", 22), all_option(50) ])

    assert_match(/<select name="pool"/, html)
    assert_match(/<select name="venue"/, html)
    assert_equal 2, html.scan("archetype-sample-label").size
  end

  # A paper-only archetype must not be offered "Online — 0 lists": the venue select answers to
  # `venue_selectable?` and to nothing else, so widening it to `selectable?` shows a control that
  # cannot change the page.
  test "a paper-only archetype is offered no venue select however many pools it has" do
    html = selector(lists_count: 50, options: [ pool_option("9", 28), pool_option("8", 22), all_option(50) ])

    assert_match(/<select name="pool"/, html)
    assert_no_match(/<select name="venue"/, html)
  end

  # The Sample select's label says "Sample", so its selected option asserts the sample's size —
  # and the pool options are venue-independent by design, so once a venue is chosen it asserts the
  # wrong one. Measured on the production data, 78 of the 171 rendered pool options do not deliver
  # their own label on a click, worst gap "All formats — 174 lists" above a 20-list report.
  test "the page says the Sample counts span both venues when a venue is chosen" do
    html = selector(lists_count: 20, online_lists_count: 20, venue: :online, venue_selectable: true,
                    options: [ pool_option("9", 118), pool_option("8", 56), all_option(174) ])

    assert_match(/The Sample counts above are over both venues/, html)
    assert_match(%r{<strong>20 lists</strong> of the venue selected beside it}, html)
  end

  # And not otherwise: with no venue chosen the Sample labels are the sample, so the sentence
  # would be qualifying something that needs no qualification.
  test "the venue note is withheld when no venue narrows the sample" do
    html = selector(lists_count: 174, online_lists_count: 20, venue_selectable: true,
                    options: [ pool_option("9", 118), pool_option("8", 56), all_option(174) ])

    assert_no_match(/The Sample counts above are over both venues/, html)
  end

  # The small-sample notice agrees in number. A one-list sample stopped being exotic with the
  # venue axis: 18 production states render it, most of them paper halves.
  test "the small sample notice agrees in number at one list" do
    one = selector(lists_count: 1, options: [ pool_option("9", 1), all_option(4) ])
    two = selector(lists_count: 2, options: [ pool_option("9", 2), all_option(4) ])

    assert_match(/describes what that list did/, one)
    assert_match(/describes what those lists did/, two)
  end

  # The pool note describes where a non-Standard list is counted, so it may only print where the
  # current sample actually holds one. An archetype whose only GLC event is paper prints it under
  # Online about a list that venue does not hold — the sample counts it nowhere, which is not what
  # the sentence says. Measured on the production data: 21 such states over 7 archetypes.
  test "the pool note withholds itself when the chosen venue holds no unpooled list" do
    html = selector(lists_count: 19, online_lists_count: 19, venue: :online, venue_selectable: true,
                    unpooled: true, unpooled_in_sample: false, pool: nil,
                    options: [ pool_option("9", 37), all_option(38) ])

    assert_no_match(/Events outside Standard/, html)
    assert_match(/<select name="venue"/, html, "sanity: the rest of the block still renders")
  end

  test "the pool note prints when the chosen venue does hold one" do
    html = selector(lists_count: 19, venue: :paper, venue_selectable: true,
                    unpooled: true, unpooled_in_sample: true, pool: nil,
                    options: [ pool_option("9", 37), all_option(38) ])

    assert_match(/Events outside Standard/, html)
  end

  # `selected:` is read off the scope. Omitted, Ui::FilterSelect marks no option and the browser
  # pre-selects the first — "All" — over a report showing Online, which is the trap the standings
  # form's division select paid for once.
  test "the venue select marks the venue the page is showing" do
    html = selector(lists_count: 20, online_lists_count: 20, venue: :online, venue_selectable: true,
                    options: [ pool_option("9", 28), all_option(28) ])

    assert_match(/<option value="online" selected>/, html)
    assert_no_match(/<option value="all" selected>/, html)
  end

  private

  # The venue members are spelled out rather than defaulted away, because a `Struct` built with
  # `keyword_init: true` stores `nil` for a keyword left out — only an *extra* one raises — so a
  # member added to the Result and forgotten here would leave every venue branch falsy and no
  # venue regression observable in any test in this file.
  def selector(lists_count:, options:, unpooled: false, pool: :default, online_lists_count: 0,
               grouping: :type, venue: :all, venue_selectable: false, venue_options: nil,
               unpooled_in_sample: nil)
    # Unpersisted on purpose: the component reads an id off each of these and nothing else —
    # `archetype_path` through `to_param`, and the pool only to decide which option is selected —
    # so this file never touches the database and cannot be broken by a fixture another test
    # destroys.
    scope = Archetypes::MetagameScope::Result.new(
      archetype: Archetype.new(id: 6, name: "Sample"), standings: nil, listed_standings: nil,
      pool: pool == :default ? StandardPool.new(id: 9) : pool,
      options: options, lists_count: lists_count, online_lists_count: online_lists_count,
      unpooled: unpooled,
      # Defaults to `unpooled` so every test written before the venue axis keeps its meaning: the
      # two only differ once a venue narrows the sample, which is what the venue test below pins.
      unpooled_in_sample: unpooled_in_sample.nil? ? unpooled : unpooled_in_sample,
      all_formats_lists_count: lists_count,
      venue: venue, venue_selectable: venue_selectable,
      venue_options: venue_options || default_venue_options(lists_count, online_lists_count)
    )

    ApplicationController.renderer.render(
      Archetypes::SampleSelector.new(scope: scope, grouping: grouping), layout: false
    )
  end

  def pool_option(value, lists)
    Archetypes::MetagameScope::Option.new(value: value, label: "Pool #{value} — #{lists} lists",
                                          lists_count: lists)
  end

  def all_option(lists)
    Archetypes::MetagameScope::Option.new(value: ALL, label: "All formats — #{lists} lists",
                                          lists_count: lists)
  end

  # Shaped the way the service builds them, so a test that does not care about the venue axis
  # still renders labels that are consistent with the counts it did pass.
  def default_venue_options(lists_count, online_lists_count)
    paper = lists_count - online_lists_count
    [ [ "all", "All", lists_count ], [ "paper", "Paper", paper ],
      [ "online", "Online", online_lists_count ] ].map do |value, label, count|
      Archetypes::MetagameScope::Option.new(
        value: value, label: "#{label} — #{count} #{'list'.pluralize(count)}", lists_count: count
      )
    end
  end
end
