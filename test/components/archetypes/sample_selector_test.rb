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

  private

  def selector(lists_count:, options:, unpooled: false, pool: :default, online_lists_count: 0,
               grouping: :type)
    # Unpersisted on purpose: the component reads an id off each of these and nothing else —
    # `archetype_path` through `to_param`, and the pool only to decide which option is selected —
    # so this file never touches the database and cannot be broken by a fixture another test
    # destroys.
    scope = Archetypes::MetagameScope::Result.new(
      archetype: Archetype.new(id: 6, name: "Sample"), standings: nil, listed_standings: nil,
      pool: pool == :default ? StandardPool.new(id: 9) : pool,
      options: options, lists_count: lists_count, online_lists_count: online_lists_count,
      unpooled: unpooled
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
end
