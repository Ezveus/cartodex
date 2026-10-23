require "application_system_test_case"
require_relative "../support/deck_card_rows"

# The set view's server rendering is held by the controller test of the same name (test/controllers/deck_set_grouping_test.rb). What only a browser sees: the
# heading count a stepper keeps true in place, and the reload a printing swap needs in this view,
# since the swapped card now belongs to another section.
class DeckSetViewTest < ApplicationSystemTestCase
  include DeckCardRows

  setup do
    @user = users(:one)
    # budew_asc is linked to the ASC set; budew_pre has no card_set and shares its fingerprint.
    @asc = cards(:budew_asc)
    @deck = @user.decks.create!(name: "Set Watch", standard_pool: standard_pools(:twm_por))
    @deck.deck_cards.create!(card: @asc, quantity: 1)
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 2)

    login_as @user, scope: :user
  end

  test "the mode links switch the list between type and set sections" do
    visit deck_path(@deck)
    assert_selector "h2", text: "Pokémon (3 — 2 unique)"
    assert_no_selector ".deck-set-section"

    within(".deck-group-modes") { click_on "Set" }

    assert_selector ".deck-set-section h2", text: "Ascended Heroes (ASC) · 1 card"
    assert_no_selector "h2", text: "Pokémon"
    assert_current_path deck_path(@deck, group: "set")

    within(".deck-group-modes") { click_on "Type" }
    assert_selector "h2", text: "Pokémon (3 — 2 unique)"
    assert_no_selector ".deck-set-section"
  end

  # Two sections, and the one driven is the second in DOM order: a controller reaching for the
  # page's first noun instead of its own section's would rewrite the wrong heading.
  test "a stepper keeps its own set heading's count and noun true, and leaves the others alone" do
    visit deck_path(@deck, group: "set")
    por_heading = ".deck-set-section[data-set-code='POR'] h2"
    asc_heading = ".deck-set-section[data-set-code='ASC'] h2"
    assert_equal %w[POR ASC], all(".deck-set-section").map { |s| s["data-set-code"] }
    assert_selector asc_heading, exact_text: "Ascended Heroes (ASC) · 1 card"

    within_quantity_of("Budew") { click_on "+" }
    assert_selector asc_heading, text: "Ascended Heroes (ASC) · 2 cards"
    assert_selector por_heading, text: "Perfect Order (POR) · 2 cards"

    # exact_text: `text:` is a substring match, which "· 1 cards" would satisfy.
    within_quantity_of("Budew") { click_on "-" }
    assert_selector asc_heading, exact_text: "Ascended Heroes (ASC) · 1 card"

    within_quantity_of("Budew") { click_on "-" }
    assert_selector asc_heading, text: "Ascended Heroes (ASC) · 0 cards"
    assert_selector por_heading, text: "Perfect Order (POR) · 2 cards"
  end

  test "a printing swap in the set view reloads, moving the card to its new set's section" do
    visit decks_path
    visit deck_path(@deck, group: "set")
    within(".deck-set-section[data-set-code='ASC']") { assert_text "Budew" }
    mark_rendered_list

    within("li.deck-card-item", text: "ASC 16") { click_on "ASC 16" }
    within(".printing-picker-menu") { click_on "PRE 4" }

    within(".deck-set-section[data-set-code='PRE']") do
      assert_selector "h2", text: "PRE · 1 card"
      assert_text "Budew"
    end
    assert_no_selector ".deck-set-section[data-set-code='ASC']"
    assert_no_selector ".deck-show-main[data-test-marker]"
    assert_current_path deck_path(@deck, group: "set")

    # `replace`: the reload took the place of the page it re-rendered rather than stacking on it.
    go_back
    assert_current_path decks_path
  end

  test "a printing swap in the type view stays in place" do
    visit deck_path(@deck)
    mark_rendered_list

    within("li.deck-card-item", text: "ASC 16") { click_on "ASC 16" }
    within(".printing-picker-menu") { click_on "PRE 4" }

    assert_selector "li.deck-card-item .deck-card-set", text: "PRE 4"
    # Checked after the swap's own effect, so the request has landed; a reload would have dropped it.
    assert_selector ".deck-show-main[data-test-marker]"
  end

  test "editing the header leaves the list in the set view" do
    visit deck_path(@deck, group: "set")

    within(".deck-actions-bar") do
      click_on "Actions ▾"
      click_on "Edit"
    end
    fill_in "Deck name", with: "Set Watch Renamed"
    click_on "Save"

    assert_selector "h1", text: "Set Watch Renamed"
    assert_selector ".deck-set-section[data-set-code='ASC']"
  end

  private

  # A Turbo visit swaps the body without reloading the window, so a window global would survive it;
  # an attribute on the rendered list does not.
  def mark_rendered_list
    page.execute_script("document.querySelector('.deck-show-main').dataset.testMarker = '1'")
  end
end

# A replace visit lands at the top of the page, so on a deck taller than the window the swapped row
# would sit below the fold. A short window makes the two-card deck such a deck.
class DeckSetViewSwapScrollTest < ApplicationSystemTestCase
  drive_at 1400, 400

  setup do
    @user = users(:one)
    @deck = @user.decks.create!(name: "Set Watch", standard_pool: standard_pools(:twm_por))
    @deck.deck_cards.create!(card: cards(:budew_asc), quantity: 1)
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 2)
    login_as @user, scope: :user
  end

  test "a printing swap in the set view keeps the swapped row on screen" do
    visit deck_path(@deck, group: "set")
    row = find("li.deck-card-item", text: "ASC 16")
    page.execute_script("arguments[0].scrollIntoView({ block: 'center' })", row)
    within(row) { click_on "ASC 16" }
    within(".printing-picker-menu") { click_on "PRE 4" }

    within(".deck-set-section[data-set-code='PRE']") { assert_text "Budew" }
    pre_row = find(".deck-set-section[data-set-code='PRE'] li.deck-card-item")
    # Not vacuous: at the top of the page the row is out of view.
    assert_operator page.evaluate_script("window.scrollY"), :>, 0
    top, bottom = page.evaluate_script(
      "(r => [r.top, r.bottom])(arguments[0].getBoundingClientRect())", pre_row
    )
    assert_operator top, :>=, 0
    assert_operator bottom, :<=, page.evaluate_script("window.innerHeight")
  end
end
