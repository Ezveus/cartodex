require "application_system_test_case"
require_relative "../support/deck_card_rows"

# Below 768px the card preview stops being a hover pane and becomes a full-screen <dialog>, opened
# by a click handler on the whole deck line — and the quantity and allocation steppers, the
# printings toggle and ⇄ sit inside that line. `card-preview#open` early-returns above the breakpoint, so the desktop half of the sweep
# swallows the same bubbled click silently and cannot see any of this.
#
# The sweep runs every other test on both sides; this file pins 390px because it is about the phone
# layout specifically, and so it runs on the mobile half only.
class DeckCardMobileTest < ApplicationSystemTestCase
  include DeckCardRows

  drive_at 390, 844

  setup do
    @user = users(:one)
    @user.collections.find_or_initialize_by(card: cards(:honedge)).update!(quantity: 3)
    @deck = @user.decks.create!(name: "Pocket Deck", physical: true, standard_pool: standard_pools(:twm_por))
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 2, owned_copies: 2)

    login_as @user, scope: :user
  end

  test "the quantity stepper adjusts the card without opening the viewer" do
    visit deck_path(@deck)

    within_quantity_of("Honedge") { click_on "+" }

    assert_selector ".deck-card-qty", text: "3"
    assert_no_selector "dialog.card-preview-modal"
  end

  test "the allocation stepper adjusts the backing without opening the viewer" do
    visit deck_path(@deck)

    within_allocation_of("Honedge") { click_on "−" }

    assert_selector ".deck-card-alloc-label", text: "1 real · 1 proxy"
    assert_no_selector "dialog.card-preview-modal"
  end

  # The printings toggle and ⇄ sit on the same lines, and both carry an action: a tap on either is
  # the control's, never the viewer's.
  test "opening the printings and moving a copy do not open the viewer" do
    @deck.deck_cards.create!(card: cards(:budew_asc), quantity: 2)

    visit deck_path(@deck)

    expand_printings_of("Budew")
    assert_no_selector "dialog.card-preview-modal"

    within(row_of("Budew")) { click_on "Other printings (1)" }
    within_printing("PRE 4") { find("button.deck-printing-move").click }

    within(row_of("Budew")) { assert_selector ".deck-card-total", exact_text: "2" }
    assert_no_selector "dialog.card-preview-modal"
  end

  # The steppers happen to be <button>s, but this codebase mostly writes clickable controls as a
  # <div> or <span> carrying data-action (archetype_picker_controller.js:141,
  # result_modal_controller.js:140, card_select_controller.js:53) — and #99 once put a printing
  # picker on this row's set/number span. A guard that only knew native interactive
  # elements would let that one through and reopen this bug, so the rule is about carrying an
  # action, not about the tag. Simulated here, since no such control is on the row today.
  test "a tap on a data-action control in the row does not open the viewer" do
    visit deck_path(@deck)

    within(row_of("Honedge")) do
      page.execute_script("arguments[0].dataset.action = 'click->deck-card-control#open'", find(".deck-card-set"))
      find(".deck-card-set").click
    end

    assert_no_selector "dialog.card-preview-modal"
  end

  # The other half of the fix: the row is still the tap target for the viewer, which is the whole
  # point of putting the action there. Deleting the action would pass the three tests above — and so
  # would a guard widened until it swallowed the row itself, which carries data-action too.
  test "tapping the card itself still opens the viewer" do
    visit deck_path(@deck)

    within(row_of("Honedge")) { find(".deck-card-name").click }

    assert_selector "dialog.card-preview-modal"
  end
end
