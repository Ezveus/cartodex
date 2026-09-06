require "test_helper"

# The section heading, which had no test at all until it started printing a second figure. Every
# assertion the suite made about `.archetype-category-header` targeted its `h3`, so the card count
# beside it had never been rendered-tested and nothing would have noticed a heading printing
# " copies" over an empty range.
#
# Structs are built by hand, the way the report's other component tests do: what this file asks
# about is presentation, and Archetypes::CardStatsTest owns the aggregation.
class Archetypes::CategorySectionTest < ActiveSupport::TestCase
  # "Beside" is a claim about the markup, not only about the strings: the header is a
  # `space-between` flex row, so two figures placed in it directly are pushed apart rather than
  # grouped. The geometry is measured in ArchetypeMetagameTest; what is checked here is the one
  # thing that makes the geometry possible, which is that both spans share a wrapper.
  test "prints the copies a list plays of the section beside the card count" do
    html = section(copies_per_list: [ 17, 20, 19, 20 ])
    meta = html[/<div class="archetype-category-meta">.*?<\/div><\/div>/m]

    assert_includes meta, "1 card"
    assert_includes meta, "17-20 copies · most often 20"
  end

  # The singular is the branch an extraction fumbles and the one nothing asserted: `copies_noun`
  # reads "copy" only when the range has collapsed *and* the number is one, and a heading printing
  # "1 copies" is the kind of thing a reader notices before any of the statistics.
  test "says one copy in the singular" do
    html = section(copies_per_list: [ 1, 1, 1 ])

    assert_includes html, "1 copy"
    assert_no_match(/1 copies/, html)
    assert_no_match(/most often/, html, "a settled number has no mode to report")
  end

  # A section played by only some lists reads from zero, which is the whole decision behind #156 —
  # see CardStats#copies_by_list. On the production data Tool is played by 12 lists of 68.
  test "reports a section some lists play none of as a range starting at zero" do
    assert_includes section(copies_per_list: [ 0, 0, 0, 1 ]), "0-1 copies · most often 0"
  end

  # A caller that built the group without a sample behind it — the styleguide, another component
  # test — must get no figure rather than a broken one. Three aggregate members with no default
  # would render " copies" here without raising.
  test "prints no copies figure for a group built without them" do
    html = section
    heading = html[/<div class="archetype-category-meta">.*?<\/div>/m]

    assert_includes heading, "1 card"
    assert_no_match(/copies/, heading, "the heading printed a figure over an empty range")
    assert_no_match(/archetype-category-copies/, html)
  end

  private

  def section(copies_per_list: [])
    entry = Archetypes::CardStats::Entry.new(
      card: Card.new(name: "Iono", set_name: "PAL", set_number: "185"),
      fingerprint: "PAL-185", inclusion_count: 4, inclusion_pct: 100.0,
      min_copies: 4, max_copies: 4, modes: [ 4 ], core: true
    )
    group = Archetypes::CardStats::NameGroup.new(
      name: "Iono", inclusion_count: 4, inclusion_pct: 100.0, entries: [ entry ]
    )
    category = Archetypes::CardStats::CategoryGroup.new(
      key: :supporter, label: "Supporter", name_groups: [ group ],
      copies_per_list: copies_per_list
    )

    Archetypes::CategorySection.new(category: category).call
  end
end
