require "application_system_test_case"

# The card page's usage tree, end to end and on both sides of the 768px breakpoint: the <details>
# open, the Venue select submits on change, a node's link lands on the analysis printing the same
# figure, and the tree — whose online event names are the longest strings this data holds — never
# pushes the page into a horizontal scroll. Geometry is read off bounding boxes, because a tree
# that overflows still renders every node a text assertion looks for.
class CardUsageSystemTest < ApplicationSystemTestCase
  setup do
    @card = Card.create!(name: "Usage System Item", card_type: "Trainer", set_name: "CUS",
                         set_number: "1", rarity: "Uncommon", subtype: "Item")
    @filler = Card.create!(name: "Usage System Filler", card_type: "Trainer", set_name: "CUS",
                           set_number: "2", rarity: "Uncommon", subtype: "Item")
    @archetype = Archetype.create!(primary_card: @card)
    pool = standard_pools(:twm_por)
    @paper = Tournament.create!(name: "Regional Championship Usage System", date: Date.new(2026, 6, 1),
                                format: "standard", standard_pool: pool, tier: "regional",
                                created_by: users(:one))
    @online = Tournament.create!(
      # No space in it: a name that cannot break on a blank is what `overflow-wrap: anywhere`
      # exists for — with spaces, the browser wraps it unaided and the rule is never exercised.
      name: "SomeExceptionallyLongOnlineWeeklyTournamentNameWithNoSpaceForTheUsageTree#42",
      date: Date.new(2026, 6, 2), format: "standard", standard_pool: pool, tier: "other",
      online: true, created_by: users(:one)
    )
    record(@paper, @card => 2)
    record(@paper, @filler => 1)
    record(@online, @card => 1)
  end

  test "a visitor opens the tree, narrows it to a venue and follows a node to the analysis" do
    visit card_path(@card)

    within "#usage" do
      archetype_summary = find(".card-usage-archetype > details > summary")
      assert_text "66.7% · 2 of 3 lists"
      archetype_summary.click
      find(".card-usage-pool > details > summary").click
      assert_selector ".card-usage-tournament", count: 2
      assert_text "#{@paper.name} (#{I18n.l(@paper.date)})"

      find("select[name=venue]").select("Online — 1 list with this card")
    end

    assert_current_path(/venue=online/)
    within "#usage" do
      assert_text "100% · 1 of 1 list · 1 copy"
      find(".card-usage-archetype > details > summary").click
      find(".card-usage-pool > details > summary").click
      assert_no_text @paper.name
      within(".card-usage-tournament", text: @online.name) { click_link "Analysis" }
    end

    # The analysis under the node's own parameters prints the same share for this card.
    assert_current_path(/analysis/)
    assert_selector ".archetype-card-pct", text: "100% of lists (1)"
  end

  test "the open tree never scrolls the page sideways, and a summary keeps its figures beside or under its name" do
    visit card_path(@card)
    page.execute_script("document.querySelectorAll('#usage details').forEach((d) => { d.open = true })")
    assert_selector ".card-usage-tournament", count: 2

    geometry = evaluate_script(<<~JS)
      (() => {
        const rows = Array.from(document.querySelectorAll("#usage .card-usage-node")).map((node) => {
          // The last line box of the name, not its bounding box: a wrapped inline name spans the
          // full width, and the figures legitimately start on its last line, after it.
          const nameLines = node.querySelector(".card-usage-name").getClientRects();
          const name = nameLines[nameLines.length - 1];
          const figures = node.querySelector(".card-usage-figures").getClientRects()[0];
          const section = document.querySelector("#usage").getBoundingClientRect();
          const all = node.querySelector(".card-usage-name").getBoundingClientRect();
          return { nameRight: all.right, figuresRight: figures.right, sectionRight: section.right,
                   besideOrUnder: figures.left >= name.right - 1 || figures.top >= name.bottom - 1 };
        });
        return { page: document.documentElement.scrollWidth - window.innerWidth, rows: rows };
      })()
    JS

    assert_operator geometry["page"], :<=, 0, "the usage tree scrolls the page sideways"
    geometry["rows"].each do |row|
      assert row["besideOrUnder"], row.inspect
      assert_operator row["figuresRight"], :<=, row["sectionRight"] + 1, row.inspect
      assert_operator row["nameRight"], :<=, row["sectionRight"] + 1, row.inspect
    end
  end

  private

  def record(event, copies_by_card)
    deck = Deck.create!(name: "Usage system list #{SecureRandom.hex(3)}", user: nil, shared: true,
                        physical: false, format: "glc")
    copies_by_card.each { |card, copies| deck.deck_cards.create!(card: card, quantity: copies) }
    TournamentStanding.create!(tournament: event, archetype: @archetype, deck: deck,
                               player_name: "Player #{SecureRandom.hex(3)}",
                               division: event.online? ? "open" : "masters", created_by: users(:one))
  end
end
