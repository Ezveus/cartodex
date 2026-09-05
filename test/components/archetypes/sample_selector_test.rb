require "test_helper"

# Three independent predicates decide what this component draws, and each of them was, until this
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

  private

  def selector(lists_count:, options:, unpooled: false, pool: :default)
    # Unpersisted on purpose: the component reads an id off each of these and nothing else —
    # `archetype_path` through `to_param`, and the pool only to decide which option is selected —
    # so this file never touches the database and cannot be broken by a fixture another test
    # destroys.
    scope = Archetypes::MetagameScope::Result.new(
      archetype: Archetype.new(id: 6, name: "Sample"), standings: nil, listed_standings: nil,
      pool: pool == :default ? StandardPool.new(id: 9) : pool,
      options: options, lists_count: lists_count, unpooled: unpooled
    )

    ApplicationController.renderer.render(
      Archetypes::SampleSelector.new(scope: scope), layout: false
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
