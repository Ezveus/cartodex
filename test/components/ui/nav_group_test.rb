require "test_helper"

# The group's whole reason to take its entries as *data* rather than as a block is that its lit
# state is then the union of its entries' sections **by construction**. A group that declared its
# own section list beside children declaring theirs would be two lists to keep in step, and the
# first entry added to a group would forget one of them — which is the same failure
# Ui::NavLinks.section_for exists to make impossible for the flat links.
#
# Every case below lights the group from somewhere other than the first entry's first section, on
# purpose: an implementation reading `entries.first.last`, or one taking a separate `sections:`
# keyword, satisfies the obvious version of this test and nothing else would catch it. The shipped
# navbars cannot separate the two either — there, the two lists agree by construction.
class Ui::NavGroupTest < ActiveSupport::TestCase
  ENTRIES = [
    [ "First",  "/first",  %w[first] ],
    [ "Second", "/second", %w[second] ],
    [ "Third",  "/third",  %w[third also_third] ]
  ].freeze

  test "the last entry's second section lights the group" do
    html = group(active_section: "also_third")

    assert_includes trigger_class(html), "active"
  end

  test "any entry's section lights the group" do
    %w[first second third also_third].each do |section|
      assert_includes trigger_class(group(active_section: section)), "active",
        "expected #{section.inspect} to light the group"
    end
  end

  test "a section belonging to no entry leaves the group unlit" do
    assert_not_includes trigger_class(group(active_section: "elsewhere")), "active"
  end

  # The visitor's navbar renders no group, but a page outside every section still renders one that
  # has to decide, and nil is what section_for can never return but a caller can always pass.
  test "no active section at all leaves the group unlit" do
    assert_not_includes trigger_class(group(active_section: nil)), "active"
  end

  # An entry may name no section — nothing in the app routes to it, or it leaves the app entirely
  # (the admin navbar's "Jobs" goes to Mission Control). It must never light its group, and the
  # empty list must not be read as "matches anything".
  test "an entry naming no section never lights the group" do
    html = group(entries: [ [ "Jobs", "/jobs", [] ] ], active_section: nil)

    assert_not_includes trigger_class(html), "active"
  end

  test "the lit leaf is the entry that owns the active section, and it alone" do
    html = Nokogiri::HTML5.fragment(group(active_section: "second"))
    active = html.css("a.navbar-link.active").map { |a| a.text.strip }

    assert_equal [ "Second" ], active
  end

  # aria-controls pointing at nothing is worse than no aria-controls: a screen reader announces a
  # relationship the page does not have. The id is derived from `id:` rather than from the label so
  # that two groups whose labels collide across navbars still differ.
  test "aria-controls names the panel's own id" do
    doc = Nokogiri::HTML5.fragment(group(id: "decks"))

    assert_equal "navbar-group-decks", doc.at_css(".navbar-group-panel")["id"]
    assert_equal "navbar-group-decks", doc.at_css(".navbar-group-trigger")["aria-controls"]
  end

  # Two elements carry the label — the button above the breakpoint, the heading below it — because
  # that is what lets the responsive switch be pure CSS and keeps aria-expanded from ever
  # contradicting what is on screen. They must never drift apart.
  test "the trigger and the drawer heading carry the same label" do
    doc = Nokogiri::HTML5.fragment(group(label: "Tournaments"))

    assert_equal "Tournaments", doc.at_css(".navbar-group-trigger").text.strip
    assert_equal "Tournaments", doc.at_css(".navbar-group-heading").text.strip
  end

  test "the trigger starts closed and says so" do
    doc = Nokogiri::HTML5.fragment(group)

    assert_equal "false", doc.at_css(".navbar-group-trigger")["aria-expanded"]
    assert_equal "button", doc.at_css(".navbar-group-trigger")["type"]
  end

  # The generic dropdown controller defaults to the class the two deck dropdowns use; the navbar's
  # panel is styled and hidden by a different one, so the value has to be declared here or the
  # controller opens nothing.
  test "the group declares the open class its own panel is hidden by" do
    doc = Nokogiri::HTML5.fragment(group)
    root = doc.at_css(".navbar-group")

    assert_equal "dropdown", root["data-controller"]
    assert_equal "navbar-group-panel--open", root["data-dropdown-open-class-value"]
  end

  # The account menu: a chip instead of a word, and the panel hung off the group's right edge
  # because it is the last thing in the row and a left-aligned panel would leave the viewport.
  test "an initial replaces the label in the trigger" do
    doc = Nokogiri::HTML5.fragment(group(label: "Account", initial: "E"))

    assert_equal "E", doc.at_css(".navbar-group-trigger .navbar-group-initial").text.strip
    assert_equal "Account", doc.at_css(".navbar-group-trigger")["aria-label"]
  end

  test "align right marks the panel rather than the group" do
    doc = Nokogiri::HTML5.fragment(group(align: :right))

    assert_includes doc.at_css(".navbar-group-panel")["class"], "navbar-group-panel--right"
  end

  # The account menu's email row and its sign-out button are not links to sections, so they arrive
  # as a block rather than as entries — and they must land inside the panel, not beside it.
  test "a block is appended inside the panel, after the entries" do
    html = Ui::NavGroup.new(label: "Account", id: "account", entries: ENTRIES).call do |group|
      group.span(class: "navbar-user") { "someone@example.test" }
    end
    doc = Nokogiri::HTML5.fragment(html)

    assert_equal "someone@example.test", doc.at_css(".navbar-group-panel .navbar-user").text.strip
    assert_equal "First", doc.at_css(".navbar-group-panel > *:first-child").text.strip
    assert_equal "someone@example.test", doc.at_css(".navbar-group-panel > *:last-child").text.strip
  end

  private

  def group(label: "Decks", id: "decks", entries: ENTRIES, active_section: nil, **rest)
    Ui::NavGroup.new(label: label, id: id, entries: entries, active_section: active_section, **rest).call
  end

  def trigger_class(html)
    Nokogiri::HTML5.fragment(html).at_css(".navbar-group-trigger")["class"]
  end
end
