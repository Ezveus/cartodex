require "application_system_test_case"

# The picker is the only place where the swap's three moving parts meet: the row it rewrites in
# place, the row it may absorb, and the deck-wide badge. A request test sees each response alone,
# so none of that is visible to one.
class DeckPrintingSwapTest < ApplicationSystemTestCase
  setup do
    # budew_pre and budew_asc share fingerprint "budew_shared" in fixtures.
    @user = users(:one)
    @asc = cards(:budew_asc)
    @pre = cards(:budew_pre)
    @deck = @user.decks.create!(name: "Printing Watch", physical: true)

    login_as @user, scope: :user
  end

  test "switching to a printing that is not owned keeps the quantity and turns the backing into proxies" do
    @user.collections.find_by!(card: @asc).update!(quantity: 2)
    @deck.deck_cards.create!(card: @asc, quantity: 3, owned_copies: 2)

    visit deck_path(@deck)
    assert_selector ".deck-card-alloc-label", text: "2 real · 1 proxy"

    open_picker_of("ASC 16")

    within(".printing-picker-menu") do
      assert_text "PRE 4"
      assert_text(/2 real .* proxies/i)
      click_on "PRE 4"
    end

    assert_selector "li.deck-card-item .deck-card-set", text: "PRE 4"
    assert_selector "li.deck-card-item .deck-card-qty", text: "3"
    assert_selector ".deck-card-alloc-label", text: "0 real · 3 proxy"
    assert_selector "turbo-frame#deck-header .badge-warning", text: "Proxies"
  end

  test "switching onto a printing already in the deck merges the two rows" do
    @deck.deck_cards.create!(card: @asc, quantity: 2)
    @deck.deck_cards.create!(card: @pre, quantity: 1)

    visit deck_path(@deck)
    assert_selector "li.deck-card-item", count: 2
    assert_selector "h2", text: "Pokémon (3 — 2 unique)"

    open_picker_of("ASC 16")
    within(".printing-picker-menu") { click_on "PRE 4" }

    assert_selector "li.deck-card-item", count: 1
    assert_selector "li.deck-card-item .deck-card-set", text: "PRE 4"
    assert_selector "li.deck-card-item .deck-card-qty", text: "3"
    assert_selector "h2", text: "Pokémon (3 — 1 unique)"
  end

  test "a card with no other printing on record offers no picker" do
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 1)

    visit deck_path(@deck)

    assert_selector "li.deck-card-item .deck-card-set", text: "POR 56"
    assert_no_selector "li.deck-card-item button.deck-card-set"
  end

  private

  def open_picker_of(set_label)
    within("li.deck-card-item", text: set_label) { click_on set_label }
  end
end
