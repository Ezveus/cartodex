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

  # The row is rewritten in place, and both steppers address their card by id. A stale one does
  # not merely 404: DeckCardQuantitySetter builds what it cannot find, so the quantity stepper
  # would silently recreate a row for the printing the swap just moved away from.
  test "the row's steppers keep working on the printing it now shows" do
    @user.collections.find_by!(card: @pre).update!(quantity: 4)
    @deck.deck_cards.create!(card: @asc, quantity: 2)

    visit deck_path(@deck)
    open_picker_of("ASC 16")
    within(".printing-picker-menu") { click_on "PRE 4" }
    assert_selector ".deck-card-alloc-label", text: "2 real · 0 proxy"

    within(".deck-card-qty-controls") { click_on "+" }
    assert_selector ".deck-card-qty", text: "3"

    within(".deck-card-alloc") { click_on "−" }
    assert_selector ".deck-card-alloc-label", text: "1 real · 2 proxy"

    rows = @deck.deck_cards.reload
    assert_equal [ @pre.id ], rows.map(&:card_id), "no row was recreated for the old printing"
    assert_equal 3, rows.sole.quantity
    assert_equal 1, rows.sole.owned_copies
  end

  test "the picker takes focus, moves it with the arrow keys, and hands it back on Escape" do
    jtg = other_printing(set_name: "JTG", set_number: "56")
    @deck.deck_cards.create!(card: @asc, quantity: 1)

    visit deck_path(@deck)
    find("button.deck-card-set-swap").send_keys(:enter)

    assert_selector ".printing-picker-menu .printing-option", count: 3
    assert_match "JTG 56", focused_text, "focus lands on the first printing that can be chosen"

    find(":focus").send_keys(:arrow_down)
    assert_match "PRE 4", focused_text

    find(":focus").send_keys(:escape)
    assert_no_selector ".printing-picker-menu .printing-option"
    assert_match "ASC 16", focused_text, "Escape hands focus back to the trigger"
    assert_equal [ @asc.id ], @deck.deck_cards.reload.map(&:card_id), "no swap happened"
    assert jtg.persisted?
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

  def focused_text
    page.evaluate_script("document.activeElement.textContent")
  end

  # A third printing of Budew. Fixtures bypass the callback that computes a fingerprint, so their
  # literal "budew_shared" has to be forced onto a created record, which gets a real digest.
  def other_printing(set_name:, set_number:)
    card = Card.create!(
      name: @pre.name, card_type: "Pokémon", hp: @pre.hp, type_symbol: @pre.type_symbol,
      retreat_cost: @pre.retreat_cost, stage: @pre.stage,
      set_name: set_name, set_number: set_number, rarity: "Common"
    )
    card.update_column(:fingerprint, @pre.fingerprint)
    card
  end
end
