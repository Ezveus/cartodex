require "test_helper"

# The row that carries the report's two claims about a card: how much of the sample plays it, and
# whether that is a settled decision or a choice. Both are said in words the reader takes at face
# value ("fixed", "most often 3"), and both are wrong in a specific, silent way if the component
# gets a case backwards — so each of those cases is pinned here rather than left to the page.
#
# Everything below is built from the service's own Structs and from unpersisted Cards: the
# component reads `card.name`, `card.printing_label` and nothing else, and the questions this file
# asks are about presentation, not about the aggregation Archetypes::CardStats already has its own
# tests for. `.call` is enough because nothing in this component tree uses a route helper — the
# trap Ui::ArchetypeBadgeTest documents does not apply here.
class Archetypes::NameGroupRowTest < ActiveSupport::TestCase
  # A name played as one card, by every list, always in the same number: the one shape that earns
  # the flag.
  test "flags a card every list plays in the same number" do
    html = row(group("Iono", 100.0, [ entry("Iono", "PAL", "185", pct: 100.0, count: 12,
                                            min: 4, max: 4, modes: [ 4 ], core: true) ]))

    assert_includes html, "archetype-fixed-flag"
    assert_includes html, ">fixed</span>"
    assert_includes html, "4 copies"
  end

  # `Entry#fixed?` is `core && single_quantity?`, and `core` is `inclusion_count == lists_count`.
  # At one list every entry satisfies both by construction, so the flag would report the sample
  # size — Archetypes::CardReport says that once in words and passes `single_list:` down instead.
  test "flags nothing at all when the sample holds one list" do
    entries = [ entry("Iono", "PAL", "185", pct: 100.0, count: 1, min: 4, max: 4,
                      modes: [ 4 ], core: true) ]

    assert_no_match(/archetype-fixed-flag/, row(group("Iono", 100.0, entries), single_list: true))
    assert_no_match(/archetype-fixed-flag/, row(split_group_with_fixed_printing, single_list: true))
  end

  # A name split across printings can be in every list at a settled count and still be a choice —
  # which printing to play — so the *name* never claims to be fixed. The printing underneath it
  # may: "every list plays SCR 114, always two of them" is a fact about that card, and this group
  # is built so that it holds. The flag has to be on the sub-row and only on the sub-row, which is
  # a distinction a bare "does the flag appear" assertion cannot make.
  test "never flags a split name, but does flag a printing that earns it" do
    html = row(split_group_with_fixed_printing)
    name_line, printings = html.split(%(<ul class="archetype-printing-list">), 2)

    assert_no_match(/archetype-fixed-flag/, name_line)
    assert_includes printings, "archetype-fixed-flag"
    # And the flagged one is the printing whose entry is fixed, not merely the first sub-row.
    assert_match(/Hoothoot \(SCR 114\)<span class="badge[^>]*archetype-fixed-flag/, printings)
  end

  # The badge follows the same rule the fixed flag does two tests above: a split name's printings
  # are genuinely different cards, so a name-level badge would assert a property of every printing
  # under it, with no way for the reader to see which actually carries it. Two printings under one
  # split name that disagree on their labels must each show only their own, and the name line must
  # show neither.
  test "badges each printing's own label on a split name, and none on the name line" do
    ace_spec = CardLabel.create!(slug: "ace-spec", name: "ACE SPEC", family: "type", position: 10)
    gust = CardLabel.create!(slug: "gust", name: "Gust", family: "type", position: 20)
    entries = [
      entry("Hoothoot", "SCR", "114", pct: 69.9, count: 65, min: 2, max: 3, modes: [ 2 ], labels: [ ace_spec ]),
      entry("Hoothoot", "PRE", "77",  pct: 39.8, count: 37, min: 1, max: 2, modes: [ 1 ], labels: [ gust ])
    ]
    html = row(group("Hoothoot", 73.1, entries, count: 68))
    name_line, printings = html.split(%(<ul class="archetype-printing-list">), 2)

    assert_no_match(/archetype-card-label/, name_line)
    assert_match(
      %r{Hoothoot \(SCR 114\)<span class="archetype-card-label-line"><span[^>]*archetype-card-label[^>]*>ACE SPEC},
      printings
    )
    assert_match(
      %r{Hoothoot \(PRE 77\)<span class="archetype-card-label-line"><span[^>]*archetype-card-label[^>]*>Gust},
      printings
    )
  end

  test "renders one sub-row per printing, and says they are not parts of the name's share" do
    html = row(split_group)

    assert_equal 3, html.scan(/class="archetype-printing-row"/).size
    assert_includes html, "Hoothoot (SCR 114)"
    assert_includes html, "Hoothoot (PRE 77)"
    assert_includes html, "Hoothoot (TEF 126)"
    # The whole reason the sub-rows are not styled as a breakdown: 69.9 + 39.8 + 2.2 is 111.9.
    assert_includes html,
                    "A list may play more than one of these printings, so their shares are not " \
                    "parts of the 73.1% above and can add up past it."
    # Copies live on the printing, never on the name: a range spanning two versions of one name
    # describes no list.
    assert_includes html, "3 printings"
  end

  # A tie is a real answer. "most often 3" would state a consensus this sample does not hold, and
  # "3 / 4" alone reads as a range or a typo.
  test "prints a tied mode as a tie" do
    html = row(group("Hoothoot", 50.0, [ entry("Hoothoot", "TEF", "126", pct: 50.0, count: 2,
                                               min: 1, max: 3, modes: [ 1, 3 ]) ]))

    assert_includes html, "1-3 copies · most often 1 / 3 — tied"
    assert_no_match(/most often 1</, html)
  end

  test "prints a single mode without the tie wording" do
    html = row(group("Hoothoot", 50.0, [ entry("Hoothoot", "TEF", "126", pct: 50.0, count: 2,
                                               min: 1, max: 3, modes: [ 2 ]) ]))

    assert_includes html, "1-3 copies · most often 2"
    assert_no_match(/tied/, html)
  end

  # phlex-rails defines a zero-argument `format` on the component, so a bare `format("%.1f", pct)`
  # raises ArgumentError instead of formatting anything — the component calls `Kernel.format`. A
  # fractional percentage is the only thing that reaches that branch: a whole one takes the
  # `pct.round.to_s` path and would render even with the bug in place.
  test "renders a fractional percentage rather than raising" do
    html = row(group("Hoothoot", 73.1, [ entry("Hoothoot", "SCR", "114", pct: 69.9, count: 65,
                                               min: 2, max: 3, modes: [ 2 ]) ]))

    assert_includes html, "73.1% of lists (65)"
    assert_includes html, "width: 73.1%"
  end

  # A whole percentage prints without its ".0" — the page prints dozens of them.
  test "drops the trailing zero on a whole percentage" do
    html = row(group("Iono", 100.0, [ entry("Iono", "PAL", "185", pct: 100.0, count: 12,
                                            min: 4, max: 4, modes: [ 4 ], core: true) ]))

    assert_includes html, "100% of lists (12)"
    assert_no_match(/100\.0%/, html)
  end

  # The end of the same rule, through the two components between the report and the row: a
  # one-list sample says so once and flags nothing, while two lists get the settled-core sentence
  # and the flags back.
  test "the report says a one-list sample is not a sample, and flags no card in it" do
    html = report(lists_count: 1, fixed_cards: 25, fixed_copies: 60)

    assert_includes html,
                    "Only one list is recorded for this sample, so there is nothing to compare " \
                    "it against — what follows is that list."
    assert_no_match(/archetype-fixed-flag/, html)
    assert_no_match(/played by every list/, html)
  end

  test "the report agrees with itself in the singular" do
    html = report(lists_count: 2, fixed_cards: 1, fixed_copies: 1)

    assert_includes html,
                    "<strong>1 card</strong> accounting for <strong>1 copy</strong> is played by " \
                    "every list"
    assert_includes html, "archetype-fixed-flag"
  end

  test "the report keeps the plural verb past one card" do
    html = report(lists_count: 2, fixed_cards: 3, fixed_copies: 8)

    assert_includes html,
                    "<strong>3 cards</strong> accounting for <strong>8 copies</strong> are " \
                    "played by every list"
  end

  private

  def row(group, single_list: false)
    Archetypes::NameGroupRow.new(group: group, single_list: single_list).call
  end

  # One fixed card, rendered through the whole report so that `single_list:` is checked where it
  # actually travels — CardReport decides it, CategorySection passes it on, NameGroupRow reads it.
  def report(lists_count:, fixed_cards:, fixed_copies:)
    entries = [ entry("Iono", "PAL", "185", pct: 100.0, count: lists_count,
                      min: 4, max: 4, modes: [ 4 ], core: true) ]
    category = Archetypes::CardStats::CategoryGroup.new(
      key: :supporter, label: "Supporter", name_groups: [ group("Iono", 100.0, entries) ]
    )
    stats = Archetypes::CardStats::Result.new(
      lists_count: lists_count, categories: [ category ],
      fixed_core_cards: fixed_cards, fixed_core_copies: fixed_copies
    )

    Archetypes::CardReport.new(stats: stats, scope: scope).call
  end

  # The report only asks the scope whether lists exist elsewhere, and only on an empty sample.
  def scope
    Archetypes::MetagameScope::Result.new(
      archetype: Archetype.new(id: 1, name: "Sample"), standings: nil, listed_standings: nil,
      pool: nil, options: [], lists_count: 0, unpooled: false
    )
  end

  # The measured production figures for Hoothoot: three genuinely different cards under one name,
  # whose shares total 111.9% of a name played by 73.1% of lists.
  def split_group
    group("Hoothoot", 73.1, [
      entry("Hoothoot", "SCR", "114", pct: 69.9, count: 65, min: 2, max: 3, modes: [ 2 ]),
      entry("Hoothoot", "PRE", "77",  pct: 39.8, count: 37, min: 1, max: 2, modes: [ 1 ]),
      entry("Hoothoot", "TEF", "126", pct: 2.2,  count: 2,  min: 1, max: 3, modes: [ 1, 3 ])
    ], count: 68)
  end

  # Every list plays SCR 114, always two of them, and a third of them also play TEF 126: the
  # printing is genuinely fixed while which printing to play is still a choice. Kept apart from
  # the production figures above, which describe a name no printing of which is core.
  def split_group_with_fixed_printing
    group("Hoothoot", 100.0, [
      entry("Hoothoot", "SCR", "114", pct: 100.0, count: 10, min: 2, max: 2, modes: [ 2 ], core: true),
      entry("Hoothoot", "TEF", "126", pct: 30.0,  count: 3,  min: 1, max: 1, modes: [ 1 ])
    ], count: 10)
  end

  # A name group's own count is the union of the lists playing any of its printings — never the
  # sum of theirs — so it is stated rather than derived from the entries here too.
  def group(name, pct, entries, count: nil)
    Archetypes::CardStats::NameGroup.new(
      name: name, inclusion_count: count || entries.first.inclusion_count, inclusion_pct: pct,
      entries: entries
    )
  end

  def entry(name, set_name, set_number, pct:, count:, min:, max:, modes:, core: false, labels: [])
    Archetypes::CardStats::Entry.new(
      card: Card.new(name: name, set_name: set_name, set_number: set_number),
      fingerprint: "#{set_name}-#{set_number}", inclusion_count: count, inclusion_pct: pct,
      min_copies: min, max_copies: max, modes: modes, core: core, labels: labels
    )
  end
end
