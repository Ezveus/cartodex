require "application_system_test_case"
require_relative "../support/deck_card_rows"

# Below 768px the card preview stops being a hover pane and becomes a full-screen <dialog>, opened
# by a click handler on the whole deck row — and the quantity and allocation steppers sit inside
# that row. None of this is reachable from the rest of the suite: `card-preview#open` early-returns
# above the breakpoint, and every other system test runs at 1400×1400, so the desktop side has been
# swallowing the same bubbled click silently for as long as it has existed.
#
# Widening the suite to both viewports properly is #98; this file resizes on its own until then.
class DeckCardMobileTest < ApplicationSystemTestCase
  include DeckCardRows

  # Asked for, not obtained: headless Chrome floors the window width, and the page actually renders
  # at innerWidth 500. Comfortably below 768, so these tests test what they claim — but a later test
  # that asserted something specific to a phone's width would not be running at one. #98 should set
  # the viewport through `driven_by screen_size:`, which is applied when the browser is created and
  # is not subject to this floor.
  MOBILE = [ 390, 844 ].freeze
  DESKTOP = [ 1400, 1400 ].freeze

  setup do
    @user = users(:one)
    @user.collections.find_or_initialize_by(card: cards(:honedge)).update!(quantity: 3)
    @deck = @user.decks.create!(name: "Pocket Deck", physical: true)
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 2, owned_copies: 2)

    login_as @user, scope: :user
    resize_to(*MOBILE)
  end

  # Selenium keeps one browser for the whole run, so a width left behind here would quietly move
  # every later test to the mobile side of the breakpoint.
  teardown { resize_to(*DESKTOP) }

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

  # The two steppers happen to be <button>s, but this codebase mostly writes clickable controls as a
  # <div> or <span> carrying data-action (archetype_picker_controller.js:141,
  # result_modal_controller.js:140, pokemon_select_controller.js:61) — and #99 means to put a
  # printing picker on this row's set/number span. A guard that only knew native interactive
  # elements would let that one through and reopen this bug, so the rule is about carrying an
  # action, not about the tag. Simulated here rather than waiting for #99 to ship it.
  test "a tap on a data-action control in the row does not open the viewer" do
    visit deck_path(@deck)

    within(row_of("Honedge")) do
      page.execute_script("arguments[0].dataset.action = 'click->printing-picker#open'", find(".deck-card-set"))
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

  private

  def resize_to(width, height)
    page.driver.browser.manage.window.resize_to(width, height)
  end
end
