require "application_system_test_case"
require_relative "../support/deck_card_rows"

# What a deck row's geometry must hold, shared by the class pinned at a phone's width and the one
# the sweep runs on both sides of the breakpoint.
#
# The row measured is the widest the page draws: a physical deck's card played in two printings,
# expanded, each sub-row carrying its quantity stepper, its owned note, ⇄, its real/proxy stepper
# and "+ add to my collection and use it here" — beside a card whose name is a long one.
module DeckRowGeometry
  include DeckCardRows

  def build_deck
    # budew_pre and budew_asc share fingerprint "budew_shared" in fixtures. Neither is owned, so
    # both in-deck printings offer to add a copy to the collection.
    @user = users(:one)
    @deck = @user.decks.create!(name: "Pocket", physical: true, standard_pool: standard_pools(:twm_por))
    @deck.deck_cards.create!(card: cards(:budew_asc), quantity: 2, owned_copies: 0)
    @deck.deck_cards.create!(card: cards(:budew_pre), quantity: 1, owned_copies: 0)
    # A real decklist is full of names like this one, and the line is a single flex row: the name
    # cannot shrink past its longest word, so it is what pushes the allocation stepper off screen.
    @deck.deck_cards.create!(card: cards(:teal_mask_ogerpon_ex), quantity: 2)

    login_as @user, scope: :user
  end

  def visit_expanded
    visit deck_path(@deck)
    expand_printings_of("Budew")

    # Not vacuous: every control the widest sub-row can carry is on screen before it is measured.
    within(row_of("Budew")) do
      assert_selector ".deck-printing-row", count: 2
      assert_selector "button.deck-printing-move", count: 2
      assert_selector "button.deck-card-collect", text: "+ add to my collection and use it here", count: 2
      assert_selector ".deck-card-alloc .qty-btn", count: 4
      assert_selector ".deck-card-qty-controls .qty-btn", count: 4
    end
  end

  # Every visible element of the list against its own row's right edge and the viewport's: a
  # control pushed past either is one the member cannot reach, or one drawn over the next column.
  def assert_nothing_overflows
    offenders = page.evaluate_script(<<~JS)
      (() => {
        const width = document.documentElement.clientWidth
        return Array.from(document.querySelectorAll(".deck-sections li *"))
          .filter((element) => element.getClientRects().length > 0)
          .flatMap((element) => {
            const rect = element.getBoundingClientRect()
            const row = element.parentElement.closest("li").getBoundingClientRect()
            const name = `${element.tagName.toLowerCase()}.${element.className} "${element.textContent.trim().slice(0, 30)}"`
            const problems = []
            if (rect.right > row.right + 0.5) problems.push(`${name}: right ${rect.right} > row ${row.right}`)
            if (rect.right > width + 0.5) problems.push(`${name}: right ${rect.right} > viewport ${width}`)
            if (rect.left < -0.5) problems.push(`${name}: left ${rect.left} < 0`)
            return problems
          })
      })()
    JS

    assert_empty offenders, "deck row content overflows at #{viewport_width}px"
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, viewport_width,
      "the page scrolls sideways"
  end

  def viewport_width
    page.evaluate_script("document.documentElement.clientWidth")
  end

  def rect_of_element(element)
    page.evaluate_script("JSON.parse(JSON.stringify(arguments[0].getBoundingClientRect()))", element)
  end

  def rect_within(element, selector)
    page.evaluate_script(
      "JSON.parse(JSON.stringify(arguments[0].querySelector('#{selector}').getBoundingClientRect()))", element
    )
  end

  def rect_of(selector)
    page.evaluate_script("JSON.parse(JSON.stringify(document.querySelector('#{selector}').getBoundingClientRect()))")
  end
end

# A deck row at a phone's width — 344px, what the browser that reported the original bug renders
# at. The sweep's mobile half bottoms out at 500 (Chrome's floor), so none of this is reachable from
# it. This is the case `drive_at` exists for, as opposed to the sweep.
#
# The row's own squeeze — set label and real/proxy label each wrapping mid-word, the last button cut
# off — was reported from a phone and does *not* reproduce in headless Chrome at this width, which
# lays a one-printing line out comfortably: the trigger was that browser rendering text larger than
# this one does. Hence the allocation test below asserts the layout rule the fix introduced (the
# allocation stepper gets a line of its own, deterministically, rather than when the browser happens
# to run out of room) — and the overflow test measures the expanded row, which is wide enough to
# overflow here when the rule is missing.
#
# The sweep runs every other test on both sides of the breakpoint; this class pins its own width
# because its assertions are about that width, and so it runs on the mobile half only.
class DeckRowNarrowTest < ApplicationSystemTestCase
  include DeckRowGeometry

  drive_at 344, 800

  setup { build_deck }

  test "sanity: the browser really is at a phone's width" do
    visit deck_path(@deck)

    assert_operator page.evaluate_script("window.innerWidth"), :<=, 400
  end

  test "the allocation stepper drops to a line of its own instead of sharing the card's" do
    visit_expanded

    lines = all(".deck-sections .deck-card-line").select { |line| line.has_selector?(".deck-card-alloc", wait: 0) }
    # The summary line's and both sub-rows', and Ogerpon's: four.
    assert_equal 4, lines.size

    lines.each do |line|
      label = line.find(".deck-card-name, .deck-card-set", match: :first).text
      quantity = rect_within(line, ".deck-card-qty-controls")
      allocation = rect_within(line, ".deck-card-alloc")

      assert_operator allocation["top"], :>=, quantity["bottom"],
        "#{label}: the real/proxy stepper is still squeezed onto the card's line"
      assert_operator allocation["right"], :<=, viewport_width,
        "#{label}: the real/proxy stepper runs off the right edge"
      # A line of its own at every width below the breakpoint, not only where the browser happens to
      # run out of room — which is the part that depended on how large it draws text.
      assert_in_delta rect_of_element(line)["width"], allocation["width"], 1,
        "#{label}: the real/proxy stepper only wrapped because it did not fit"
    end
  end

  test "an expanded physical row keeps every control inside the row and the screen" do
    visit_expanded

    assert_nothing_overflows
  end

  # The sub-rows are indented under the card they belong to, and each indent costs width a 344px
  # screen does not have to spare — what used to be the picker's menu hanging off the screen.
  test "⇄ still moves a copy from a narrow screen" do
    visit_expanded

    within_printing("PRE 4") { find("button.deck-printing-move").click }

    within_printing("PRE 4") { assert_selector ".deck-card-qty", exact_text: "2" }
    within_printing("ASC 16") { assert_selector ".deck-card-qty", exact_text: "1" }
    assert_nothing_overflows
    assert_equal 2, @deck.deck_cards.find_by!(card: cards(:budew_pre)).quantity
  end

  # The styleguide renders the real row on its own, expanded, inside a demo box: a narrow-screen
  # rule that only holds inside the deck page's own layout would send it out of that box.
  test "the styleguide's deck row stays inside its demo box" do
    visit "/styleguide"

    demo = rect_of(".sg-deck-row-demo")
    row = rect_of(".sg-deck-row-demo li.deck-fingerprint")

    assert_operator row["right"], :<=, demo["right"] + 1, "the demo row escapes its box on the right"
    assert_operator row["bottom"], :<=, demo["bottom"] + 1, "the demo row escapes its box at the bottom"
    widest = page.evaluate_script(<<~JS)
      Math.max(...Array.from(document.querySelectorAll(".sg-deck-row-demo li *"))
        .filter((element) => element.getClientRects().length > 0)
        .map((element) => element.getBoundingClientRect().right))
    JS
    assert_operator widest, :<=, demo["right"] + 1, "a control of the demo row escapes its box"
  end
end

# The same row at the sweep's own viewport — 500px on the mobile half (Chrome's window floor), 1400
# on the desktop one — so the overflow check runs at the default width of each side and not only
# at the pinned one.
class DeckRowGeometryTest < ApplicationSystemTestCase
  include DeckRowGeometry

  setup { build_deck }

  test "an expanded physical row keeps every control inside the row and the screen" do
    visit_expanded

    assert_nothing_overflows
  end
end

# Just above the breakpoint the preview pane still takes 300px beside the list, so the list column
# is at its narrowest on the desktop side — narrower than the 500px phone the mobile half renders.
# The desktop rule has to hold there too, not only at the sweep's 1400.
class DeckRowNarrowDesktopTest < ApplicationSystemTestCase
  include DeckRowGeometry

  drive_at 800, 900

  setup { build_deck }

  test "an expanded physical row keeps every control inside the row and the screen" do
    visit_expanded

    assert_nothing_overflows
  end
end
