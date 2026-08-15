require "application_system_test_case"

# A deck row at a phone's width — 344px, what the browser that reported the bug renders at. The
# sweep's mobile half bottoms out at 500 (Chrome's floor), so none of this is reachable from it:
# the picker's menu hangs 42px off the left edge here, and 10px off it even at 500 — barely visible
# there, which is how it shipped. This is the case `drive_at` exists for, as opposed to the sweep.
#
# The row's own squeeze — set label and real/proxy label each wrapping mid-word, the last button cut
# off — was reported from a phone and does *not* reproduce here: headless Chrome lays the row out
# comfortably at this width, so the trigger is that browser rendering text larger than this one
# does. Hence the row test below asserts the layout rule the fix introduces (the allocation stepper
# gets a line of its own, deterministically, rather than when the browser happens to run out of
# room) instead of "nothing is clipped" — which passes here either way and would prove nothing.
#
# The sweep runs every other test on both sides of the breakpoint; this class pins its own width
# because its assertions are about that width, and so it runs on the mobile half only.
class DeckRowNarrowTest < ApplicationSystemTestCase
  drive_at 344, 780

  setup do
    # budew_pre and budew_asc share fingerprint "budew_shared" in fixtures.
    @user = users(:one)
    @asc = cards(:budew_asc)
    @user.collections.find_by!(card: @asc).update!(quantity: 2)
    @deck = @user.decks.create!(name: "Pocket", physical: true)
    @deck.deck_cards.create!(card: @asc, quantity: 3, owned_copies: 2)
    # A real decklist is full of names like this one, and the row is a single flex line: the name
    # cannot shrink past its longest word, so it is what pushes the allocation stepper off screen.
    @deck.deck_cards.create!(card: cards(:teal_mask_ogerpon_ex), quantity: 2)

    login_as @user, scope: :user
  end

  test "sanity: the browser really is at a phone's width" do
    visit deck_path(@deck)

    assert_operator page.evaluate_script("window.innerWidth"), :<=, 400
  end

  test "the allocation stepper drops to a line of its own instead of sharing the card's" do
    visit deck_path(@deck)

    all("li.deck-card-item").each do |row|
      label = row.find(".deck-card-name").text
      name = rect_within(row, ".deck-card-name")
      allocation = rect_within(row, ".deck-card-alloc")

      assert_operator allocation["top"], :>=, name["bottom"],
        "#{label}: the real/proxy stepper is still squeezed onto the card's line"
      assert_operator allocation["right"], :<=, viewport_width,
        "#{label}: the real/proxy stepper runs off the right edge"
      # A line of its own at every width below the breakpoint, not only where the browser happens to
      # run out of room — which is the part that depended on how large it draws text.
      assert_in_delta rect_of_element(row)["width"], allocation["width"], 1,
        "#{label}: the real/proxy stepper only wrapped because it did not fit"
    end
  end

  test "the printing picker's menu stays inside the screen" do
    visit deck_path(@deck)
    find("button.deck-card-set-swap").click
    assert_selector ".printing-picker-menu .printing-option"

    row = find("button.deck-card-set-swap").ancestor("li.deck-card-item")
    rect = rect_of(".printing-picker-menu")

    assert_operator rect["left"], :>=, 0, "the menu hangs off the left edge of the screen"
    assert_operator rect["right"], :<=, viewport_width, "the menu hangs off the right edge of the screen"
    # It is a sheet under the row, not a dropdown hanging off a label that happens to sit far enough
    # from the edge: where the label lands depends on how wide everything beside it renders.
    assert_in_delta rect_of_element(row)["width"], rect["width"], 1,
      "the menu is anchored to the set label rather than to the row"
  end

  # Anchoring the menu to the row rather than to the set/number label is what keeps it on screen —
  # and it must still be the row's own menu, not something spanning the page.
  test "the picker still swaps the printing from a narrow screen" do
    visit deck_path(@deck)
    find("button.deck-card-set-swap").click
    within(".printing-picker-menu") { click_on "PRE 4" }

    assert_selector ".deck-card-set", text: "PRE 4"
    assert_includes @deck.deck_cards.reload.map(&:card_id), cards(:budew_pre).id
  end

  # The picker's narrow-screen rules re-anchor its menu to the deck row — an ancestor that is not
  # part of the component. The styleguide renders the picker on its own, inside a box sized to hold
  # the menu, and an unscoped rule sends it straight out of that box and over the next section.
  test "the styleguide's standalone picker keeps its menu inside the demo box" do
    visit "/styleguide"

    demo = rect_of(".sg-printing-demo")
    menu = rect_of(".sg-printing-demo .printing-picker-menu")

    assert_operator menu["bottom"], :<=, demo["bottom"] + 1,
      "the demo's menu escapes the box the page reserves for it"
  end

  private

  def viewport_width
    page.evaluate_script("document.documentElement.clientWidth")
  end

  def rect_of_element(element)
    page.evaluate_script("JSON.parse(JSON.stringify(arguments[0].getBoundingClientRect()))", element)
  end

  def rect_within(row, selector)
    page.evaluate_script(
      "JSON.parse(JSON.stringify(arguments[0].querySelector('#{selector}').getBoundingClientRect()))", row
    )
  end

  def rect_of(selector)
    page.evaluate_script("JSON.parse(JSON.stringify(document.querySelector('#{selector}').getBoundingClientRect()))")
  end
end
