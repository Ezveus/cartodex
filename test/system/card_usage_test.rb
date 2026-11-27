require "application_system_test_case"

# The card page's usage tree, end to end and on both sides of the 768px breakpoint: the <details>
# open, the filters submit on change, a node's link lands on the analysis printing the same
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

  # The cascade a reader clicks through: a pool, then one of its events, then that event's figure on
  # the analysis it links to.
  test "a visitor narrows the tree to a pool, then to one event, and follows it to the analysis" do
    glc = Tournament.create!(name: "League Cup Usage System", date: Date.new(2026, 4, 1), format: "glc",
                             tier: "league_cup", created_by: users(:one))
    record(glc, @card => 3)
    pool = standard_pools(:twm_por)
    visit card_path(@card)

    within("#usage") { find("select[name=pool]").select("#{pool.name} — 2 lists with this card") }
    assert_current_path(/pool=#{pool.id}/)
    within "#usage" do
      assert_text "#{pool.name} · 66.7% · 2 of 3 lists"
      find("select[name=tournament]").select("#{@paper.name} (#{I18n.l(@paper.date)}) — 1 list with this card")
    end

    assert_current_path(/tournament=#{@paper.id}/)
    within "#usage" do
      assert_no_selector "details"
      assert_text "50% · 1 of 2 lists · 2 copies"
      click_link "Analysis"
    end

    assert_current_path(/analysis/)
    assert_selector ".archetype-card-pct", text: "50% of lists (1)"
  end

  test "the open tree never scrolls the page sideways, and a summary keeps its figures beside or under its name" do
    # A GLC list playing the card, so all three selects render: the Tournament select is as wide as
    # its longest option, the space-less online name.
    record(Tournament.create!(name: "League Cup Usage System", date: Date.new(2026, 4, 1), format: "glc",
                              tier: "league_cup", created_by: users(:one)), @card => 1)
    visit card_path(@card)
    assert_selector "#usage select", count: 3
    page.execute_script("document.querySelectorAll('#usage details').forEach((d) => { d.open = true })")
    assert_selector ".card-usage-tournament", count: 3

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
        const section = document.querySelector("#usage").getBoundingClientRect();
        const selects = Array.from(document.querySelectorAll("#usage select"))
          .map((select) => select.getBoundingClientRect().right - section.right);
        return { page: document.documentElement.scrollWidth - window.innerWidth, rows: rows, selects: selects };
      })()
    JS

    assert_operator geometry["page"], :<=, 0, "the usage tree scrolls the page sideways"
    geometry["selects"].each { |overhang| assert_operator overhang, :<=, 1, "a filter select overflows the section" }
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
