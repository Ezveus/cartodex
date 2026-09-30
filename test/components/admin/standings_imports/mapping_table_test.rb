require "test_helper"

# The arbitration table of an event import. What it owes the admin is to make the few lines that
# need them impossible to miss among the many that do not — measured on event 578, 3 of 28 — and
# to let them create a missing archetype from the line itself.
#
# Rendered with a bare `.call`: nothing here reads a route helper or the request.
class Admin::StandingsImports::MappingTableTest < ActiveSupport::TestCase
  Line = Admin::StandingsImportsController::MappingLine
  Proposal = Tournaments::ArchetypeProposer::Proposal

  setup do
    @ogerpon = archetypes(:ogerpon)
    @marker = archetypes(:standings_marker)
    @card = cards(:teal_mask_ogerpon_ex)
    @budew = cards(:budew_asc)
  end

  # The fixture order interleaves the groups, and within each group puts the lines in a known order,
  # so that a sort which is not stable — or one keyed on the verdict rather than on what the line
  # asks — reorders something this test can see.
  test "lines needing a decision come first, then proposals, then confirmations, each in event order" do
    html = table(
      confirmed_line("100"), proposed_line("200"), unresolved_line("300", :no_candidate),
      confirmed_line("400"), error_line("500"), proposed_line("600"), unresolved_line("700", :ambiguous)
    )

    assert_equal %w[300 500 700 200 600 100 400], references(html)
  end

  test "each row carries the level of attention it asks for" do
    html = table(unresolved_line("1", :name_says_nothing), error_line("2"), proposed_line("3"), confirmed_line("4"))

    assert_equal %w[decide decide check confirmed], rows(html).map { |row| modifier(row) }
  end

  # The badge colour is the other half of standing out, and it is per level rather than per verdict:
  # an unreadable list asks the same thing of the admin as "no candidate" does.
  test "badges are danger to decide, warning to check, success when confirmed" do
    html = table(unresolved_line("1", :no_candidate), error_line("2"), proposed_line("3"), confirmed_line("4"))

    badges = rows(html).map { |row| row.at_css("[data-label=Proposal] .badge")["class"].split - [ "badge" ] }
    assert_equal [ [ "badge-danger" ], [ "badge-danger" ], [ "badge-warning" ], [ "badge-success" ] ], badges
  end

  test "the summary counts each group and leaves out an empty one" do
    html = table(unresolved_line("1", :no_candidate), proposed_line("2"), proposed_line("3"))
    assert_equal [ "1 to decide", "2 proposals to check" ], summary(html)
  end

  # Offered on every line, the confirmed ones included: the owner's call, because a confirmation can
  # be wrong precisely because the right archetype did not exist when it was made.
  test "every line offers a new archetype" do
    html = table(unresolved_line("1", :no_candidate), proposed_line("2"), confirmed_line("3"), error_line("4"))

    rows(html).each do |row|
      button = row.at_css("button.standings-import-mapping-new")
      assert button, "#{row.at_css('.standings-import-reference').text} has no button"
      assert_nil button["hidden"]
      assert_equal "mapping-archetype#toggle", button["data-action"]
      assert row.at_css(".standings-import-mapping-create[hidden]")
    end
  end

  test "the create section is pre-filled with the suggested cards, primary first" do
    line = unresolved_line("371", :no_candidate, suggested: [ @card, @budew ])
    section = rows(table(line)).first.at_css(".standings-import-mapping-create")

    assert_equal @card.id.to_s, section.at_css("[data-mapping-archetype-target=primaryId]")["value"]
    assert_equal @budew.id.to_s, section.at_css("[data-mapping-archetype-target=secondaryId]")["value"]
    assert_equal [ @card.printing_label, @budew.printing_label ],
      section.css("input[type=text]").map { |input| input["value"] }
  end

  # A proposal built without suggestions (as the controller's own tests stub one) and a confirmed
  # line with no proposal at all both open empty rather than raising.
  test "a line with no suggestion opens an empty search" do
    bare = Line.new(reference: "9", label: "Nine",
      proposal: Proposal.new(archetype: nil, verdict: :no_candidate, candidates: []))
    section = rows(table(bare, confirmed_line("10"))).map { |row| row.at_css(".standings-import-mapping-create") }

    section.each do |node|
      assert_nil node.at_css("[data-mapping-archetype-target=primaryId]")["value"]
      assert_nil node.at_css("input[type=text]")["value"]
    end
  end

  # The section sits inside the form that stores every mapping and enqueues the run. A named input
  # in it would ride that POST — and `mapping_selections` reads any key it can parse.
  test "nothing inside the create section is submitted with the confirm form" do
    html = table(unresolved_line("1", :no_candidate, suggested: [ @card ]))
    section = rows(html).first.at_css(".standings-import-mapping-create")

    assert_not_empty section.css("input")
    assert_empty section.css("input[name], select[name], textarea[name]")
    section.css("button").each { |button| assert_equal "button", button["type"] }
  end

  # Enter in a text field submits its form, which here is "Confirm mappings and import".
  test "enter is swallowed on both card searches" do
    section = rows(table(unresolved_line("1", :no_candidate))).first.at_css(".standings-import-mapping-create")

    section.css("input[type=text]").each do |input|
      assert_includes input["data-action"], "keydown.enter->mapping-archetype#swallowEnter"
      # And typing forgets the card the search held, or an erased pre-fill still rides the create.
      assert_includes input["data-action"], "input->mapping-archetype#forget"
    end
    assert_equal 2, section.css("input[type=text]").size
  end

  # Event 578's own shape, 28 lines. Ruby's sort_by happens to keep tied items in input order up to
  # 16 of them and not beyond, so the seven-line test above cannot tell a stable sort from an
  # unstable one — this one can.
  test "the order stays the event's own within a group on an event-sized table" do
    lines = Array.new(28) { |i| confirmed_line(i.to_s) }
    lines[5] = proposed_line("5")
    lines[17] = proposed_line("17")
    lines[20] = unresolved_line("20", :no_candidate)

    assert_equal [ "20", "5", "17", *((0..27).map(&:to_s) - %w[5 17 20]) ], references(table(*lines))
  end

  # The row is the Stimulus controller's element, and every target it drives must sit inside it —
  # a `row` that merged the class and dropped `data:` would leave every button dead.
  test "each row is its own mapping-archetype controller holding all its targets" do
    rows(table(unresolved_line("1", :no_candidate, suggested: [ @card ]), confirmed_line("2"))).each do |row|
      assert_equal "mapping-archetype", row["data-controller"]
      %w[select createSection createButton primaryId secondaryId].each do |target|
        assert_equal 1, row.css("[data-mapping-archetype-target=#{target}]").size, target
      end
      # The same hidden input is card-select's own field, which is what its search result writes.
      assert_equal 2, row.css("[data-card-select-target=hiddenField][data-mapping-archetype-target]").size
    end
  end

  test "the summary says one proposal in the singular, and names the confirmed group" do
    html = table(unresolved_line("1", :no_candidate), unresolved_line("2", :ambiguous), error_line("3"),
      proposed_line("4"), confirmed_line("5"), confirmed_line("6"))

    assert_equal [ "3 to decide", "1 proposal to check", "2 confirmed earlier" ], summary(html)
    assert_equal [ "2 confirmed earlier" ], summary(table(confirmed_line("5"), confirmed_line("6")))
  end

  test "an event with no deck line prints no summary" do
    assert_nil Nokogiri::HTML5.fragment(table).at_css(".standings-import-mapping-summary")
  end

  private

  def table(*lines)
    Admin::StandingsImports::MappingTable.new(lines: lines, archetypes: Archetype.order(:name)).call
  end

  def summary(html)
    Nokogiri::HTML5.fragment(html).css(".standings-import-mapping-summary .badge").map { |badge| badge.text.strip }
  end

  def rows(html) = Nokogiri::HTML5.fragment(html).css(".data-table-body > .data-table-row")
  def references(html) = rows(html).map { |row| row.at_css(".standings-import-reference").text }
  def modifier(row) = row["class"][/standings-import-mapping--(\w+)/, 1]

  def confirmed_line(reference) = Line.new(reference: reference, label: "Deck #{reference}", confirmed: @ogerpon)

  def proposed_line(reference)
    Line.new(reference: reference, label: "Deck #{reference}",
      proposal: Proposal.new(archetype: @marker, verdict: :decided, candidates: [ @marker ], suggested_cards: []))
  end

  def unresolved_line(reference, verdict, suggested: [])
    Line.new(reference: reference, label: "Deck #{reference}",
      proposal: Proposal.new(archetype: nil, verdict: verdict, candidates: [], suggested_cards: suggested))
  end

  def error_line(reference) = Line.new(reference: reference, label: "Deck #{reference}", error: "Limitless published no list")
end
