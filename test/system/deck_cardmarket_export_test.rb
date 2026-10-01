require "application_system_test_case"
require_relative "../support/deck_card_rows"

# The one part of the missing-copies Cardmarket wishlist (#208) a request test cannot see: that the
# clipboard button says "nothing to buy" in its own label instead of copying an empty list. The
# notice reaches the screen only through clipboard_controller, and this repository has no JS tests.
#
# The second half proves the answer is read at click time rather than baked into the page: the
# menu is rendered once, and the steppers change what the deck backs underneath it.
#
# navigator.clipboard.writeText is replaced by a recorder, so what was written is asserted rather
# than inferred from the label — headless Chrome may refuse the real write, and the notice path
# must write nothing at all.
class DeckCardmarketExportTest < ApplicationSystemTestCase
  include DeckCardRows

  MISSING = "Copy as Cardmarket wishlist (missing copies)".freeze

  setup do
    @user = users(:one)
    @user.collections.find_or_initialize_by(card: cards(:honedge)).update!(quantity: 2)
    @deck = @user.decks.create!(name: "Fully Owned", physical: true, standard_pool: standard_pools(:twm_por))
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 2, owned_copies: 2)

    login_as @user, scope: :user
  end

  test "a fully backed deck says there is nothing to buy, and copies the proxy once there is one" do
    visit deck_path(@deck)
    execute_script(<<~JS)
      window.__clipboardWrites = []
      Object.defineProperty(navigator, "clipboard", {
        configurable: true,
        value: { writeText: (text) => { window.__clipboardWrites.push(text); return Promise.resolve() } }
      })
    JS

    click_on "Export ▾"
    click_on MISSING

    assert_selector ".dropdown-item", text: Decks::CardmarketExporter::NOTHING_TO_BUY
    assert_equal [], evaluate_script("window.__clipboardWrites")
    # The label goes back, so the item can be clicked again.
    assert_selector ".dropdown-item", text: MISSING, wait: 5

    within_allocation_of("Honedge") { click_on "−" }
    assert_selector ".deck-card-alloc-label", text: "1 real · 1 proxy"

    click_on "Export ▾" unless has_selector?(".dropdown-item", text: MISSING, wait: 0)
    click_on MISSING

    assert_selector ".dropdown-item", text: "Copied!"
    assert_equal [ "Honedge Cut\n" ], evaluate_script("window.__clipboardWrites")
  end
end
