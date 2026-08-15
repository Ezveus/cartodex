require "application_system_test_case"

# Below 768px the card preview stops being a hover pane and becomes a full-screen <dialog>, opened
# by a click handler on the whole deck row — and the quantity and allocation steppers sit inside
# that row. None of this is reachable from the rest of the suite: `card-preview#open` early-returns
# above the breakpoint, and every other system test runs at 1400×1400, so the desktop side has been
# swallowing the same bubbled click silently for as long as it has existed.
#
# Widening the suite to both viewports properly is #98; this file resizes on its own until then.
class DeckCardMobileTest < ApplicationSystemTestCase
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

    within_row_of("Honedge") { click_on "+" }

    assert_selector ".deck-card-qty", text: "3"
    assert_no_selector "dialog.card-preview-modal"
  end

  test "the allocation stepper adjusts the backing without opening the viewer" do
    visit deck_path(@deck)

    within_allocation_of("Honedge") { click_on "−" }

    assert_selector ".deck-card-alloc-label", text: "1 real · 1 proxy"
    assert_no_selector "dialog.card-preview-modal"
  end

  # The other half of the fix: the row is still the tap target for the viewer, which is the whole
  # point of putting the action there. Deleting the action would pass the two tests above.
  test "tapping the card itself still opens the viewer" do
    visit deck_path(@deck)

    within(row_of("Honedge")) { find(".deck-card-name").click }

    assert_selector "dialog.card-preview-modal"
  end

  private

  def resize_to(width, height)
    page.driver.browser.manage.window.resize_to(width, height)
  end

  # Mirrors DeckProxyBadgeTest: the allocation stepper's "−" is a minus sign, the quantity
  # stepper's "-" an ASCII hyphen, so the two scopes cannot be collapsed into one.
  def within_allocation_of(card_name, &block)
    within(row_of(card_name)) { within(".deck-card-alloc", &block) }
  end

  def within_row_of(card_name, &block)
    within(row_of(card_name)) { within(".deck-card-qty-controls", &block) }
  end

  def row_of(card_name)
    find("li.deck-card-item", text: card_name)
  end
end
