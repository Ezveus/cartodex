require "application_system_test_case"
require_relative "../support/deck_card_rows"

# Every write on the deck page is answered with the card's rows and every section's counts, and
# deck_rows_controller.js places them — no reload, no number computed in the browser. A request test
# sees the answer; only a browser sees it land: in the right section, in name order, with the
# headings, the deck total and the Proxies badge kept true, and the member's focus kept.
class DeckRowsInPlaceTest < ApplicationSystemTestCase
  include DeckCardRows

  setup do
    @user = users(:one)
    @honedge = cards(:honedge)
    @deck = @user.decks.create!(name: "In Place", physical: true, standard_pool: standard_pools(:twm_por))

    login_as @user, scope: :user
  end

  # The bug the server-computed bounds exist for: the browser kept the real +'s bound from the
  # render, so after a quantity + it refused the real + until a reload.
  test "with a free copy in the collection, the steppers' bounds follow every write" do
    @user.collections.find_by!(card: @honedge).update!(quantity: 3)
    @deck.deck_cards.create!(card: @honedge, quantity: 2, owned_copies: 2)

    visit deck_path(@deck)
    mark_page

    # The + claims the free copy itself.
    within_quantity_of("Honedge") { click_on "+" }
    within(line_of("Honedge")) do
      assert_selector ".deck-card-qty", exact_text: "3"
      assert_selector ".deck-card-alloc-label", exact_text: "3 real · 0 proxy"
      assert_selector ".deck-card-alloc button[disabled]", text: "+"
    end

    within_allocation_of("Honedge") { click_on "−" }
    within(line_of("Honedge")) { assert_selector ".deck-card-alloc-label", exact_text: "2 real · 1 proxy" }

    # Bounded by the render's max of 2, this click would have been refused.
    within_allocation_of("Honedge") { click_on "+" }
    within(line_of("Honedge")) { assert_selector ".deck-card-alloc-label", exact_text: "3 real · 0 proxy" }
    assert_no_selector ".deck-card-collect"
    assert_page_not_reloaded

    assert_equal [ 3, 3 ], @deck.deck_cards.find_by!(card: @honedge).values_at(:quantity, :owned_copies)
  end

  test "with no free copy, a proxy offers to add one to the collection and backs itself with it" do
    @user.collections.find_by!(card: @honedge).update!(quantity: 2)
    @deck.deck_cards.create!(card: @honedge, quantity: 2, owned_copies: 2)

    visit deck_path(@deck)
    assert_no_selector ".deck-card-collect"
    mark_page

    within_quantity_of("Honedge") { click_on "+" }
    within(line_of("Honedge")) do
      assert_selector ".deck-card-alloc-label", exact_text: "2 real · 1 proxy"
      assert_selector ".deck-card-alloc button[disabled]", text: "+"
      click_on "+ add to my collection and use it here"
    end

    within(line_of("Honedge")) { assert_selector ".deck-card-alloc-label", exact_text: "3 real · 0 proxy" }
    assert_no_selector ".deck-card-collect"
    assert_no_selector "turbo-frame#deck-header .badge-warning", text: "Proxies"
    assert_page_not_reloaded

    assert_equal 3, @user.collections.where(card: @honedge).sum(:quantity)
    assert_equal [ 3, 3 ], @deck.deck_cards.find_by!(card: @honedge).values_at(:quantity, :owned_copies)
  end

  # A Trainer is the case where the answer has to build two levels of section at once — the
  # "Trainer" group and its subsection — and put the group between two sections the page holds.
  test "a card added from the search lands in its section, in name order, building the section it needs" do
    @deck.update!(physical: false)
    @deck.deck_cards.create!(card: cards(:budew_asc), quantity: 1)
    @deck.deck_cards.create!(card: @honedge, quantity: 2)
    @deck.deck_cards.create!(card: cards(:basic_psychic_energy), quantity: 4)

    visit deck_path(@deck)
    assert_equal %w[pokemon energy], top_sections
    assert_equal "7", deck_total
    mark_page

    add_from_search("Doublade", "POR 57")
    assert_equal %w[Budew Doublade Honedge], names_in("pokemon")
    assert_selector section_heading("pokemon"), exact_text: "Pokémon (4 — 3 unique)"
    assert_equal "8", deck_total

    add_from_search("Boss", "MEG 114")
    within("[data-section-key='trainer']") do
      assert_selector "h2", exact_text: "Trainer"
      assert_selector ".deck-subsection[data-section-key='trainer-other'] h3", exact_text: "Other (1 — 1 unique)"
      assert_text "Boss's Orders"
    end
    assert_equal %w[pokemon trainer energy], top_sections
    assert_equal "9", deck_total

    # Another printing of a card the deck holds joins its row rather than making a second one.
    add_from_search("Budew", "PRE 4")
    assert_equal %w[Budew Doublade Honedge], names_in("pokemon")
    within(row_of("Budew")) do
      assert_selector ".deck-card-total", exact_text: "2"
      assert_button "2 printings"
    end
    assert_selector section_heading("pokemon"), exact_text: "Pokémon (5 — 3 unique)"
    assert_equal "10", deck_total
    assert_page_not_reloaded
  end

  test "in the set view a card from a set the page does not show builds that section in its place" do
    @deck.update!(physical: false)
    @deck.deck_cards.create!(card: cards(:budew_asc), quantity: 1)
    @deck.deck_cards.create!(card: cards(:budew_pre), quantity: 1)

    visit deck_path(@deck, group: "set")
    assert_equal %w[ASC PRE], set_codes
    mark_page

    # POR was released after ASC, and the newest set comes first.
    add_from_search("Honedge", "POR 56")
    assert_equal %w[POR ASC PRE], set_codes
    assert_selector ".deck-set-section[data-set-code='POR'] h2", exact_text: "Perfect Order (POR) · 1 card"
    assert_equal "3", deck_total
    assert_page_not_reloaded
  end

  test "removing the last copy takes the row and its emptied section, and the badge follows" do
    @user.collections.find_by!(card: @honedge).update!(quantity: 2)
    @deck.deck_cards.create!(card: @honedge, quantity: 2, owned_copies: 2)
    @deck.deck_cards.create!(card: cards(:basic_psychic_energy), quantity: 1, owned_copies: 0)

    visit deck_path(@deck)
    assert_equal %w[pokemon energy], top_sections
    assert_selector "turbo-frame#deck-header .badge-warning", text: "Proxies"
    mark_page

    within_quantity_of("Psychic Energy") { click_on "-" }

    assert_no_selector ".deck-sections [data-row-key]", text: "Psychic Energy"
    assert_equal %w[pokemon], top_sections
    assert_equal "2", deck_total
    assert_no_selector "turbo-frame#deck-header .badge-warning", text: "Proxies"

    within_quantity_of("Honedge") { click_on "-" }
    within(line_of("Honedge")) { assert_selector ".deck-card-alloc-label", exact_text: "1 real · 0 proxy" }
    assert_selector section_heading("pokemon"), exact_text: "Pokémon (1 — 1 unique)"
    assert_equal "1", deck_total
    assert_page_not_reloaded
  end

  # The redraw replaces the button that was clicked; without refocusing, a keyboard user is left
  # at the top of the document after every step.
  test "after a step, focus is on the redrawn button that took it" do
    @deck.deck_cards.create!(card: @honedge, quantity: 1)

    visit deck_path(@deck)
    plus = within_quantity_of("Honedge") { find("button", text: "+") }
    execute_script("arguments[0].dataset.testOld = '1'", plus)
    plus.click

    within(line_of("Honedge")) { assert_selector ".deck-card-qty", exact_text: "2" }
    focused = evaluate_script(
      "({ key: document.activeElement.dataset.focusKey, old: document.activeElement.dataset.testOld ?? null })"
    )
    assert_equal "qty-plus-#{@honedge.id}", focused["key"]
    assert_nil focused["old"], "focus stayed on the button the redraw dropped"

    # And the keyboard can keep going from there.
    find(":focus").send_keys(:enter)
    within(line_of("Honedge")) { assert_selector ".deck-card-qty", exact_text: "3" }
  end

  private

  def add_from_search(query, set_label)
    find(".card-search-input").set(query)
    find(".card-search-result-item", text: set_label).find(".card-search-add-btn").click
    assert_no_selector ".card-search-result-item"
  end

  def top_sections
    all(".deck-sections > [data-section-key]").map { |section| section["data-section-key"] }
  end

  def set_codes
    all(".deck-set-section").map { |section| section["data-set-code"] }
  end

  def section_heading(key)
    ".deck-section[data-section-key='#{key}'] > h2"
  end

  def names_in(key)
    all(".deck-section[data-section-key='#{key}'] > ul.deck-card-list > li > .deck-card-line .deck-card-name").map(&:text)
  end
end

# The public page draws the same rows read-only: a card played in several printings still opens
# onto each printing's count, and nothing on it writes or reads the owner's collection.
class DeckRowsPublicTest < ApplicationSystemTestCase
  include DeckCardRows

  setup do
    @deck = users(:two).decks.create!(name: "Shared Budew", shared: true, standard_pool: standard_pools(:twm_por))
    @deck.deck_cards.create!(card: cards(:budew_asc), quantity: 2)
    @deck.deck_cards.create!(card: cards(:budew_pre), quantity: 1)
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 1)
  end

  test "a visitor opens a card's printings onto their counts, with no control that writes" do
    visit deck_path(@deck)

    within(row_of("Budew")) do
      assert_selector ".deck-card-total", exact_text: "3"
      assert_no_selector ".deck-printing-row"
    end
    expand_printings_of("Budew")

    within_printing("ASC 16") { assert_selector ".deck-card-qty", exact_text: "2" }
    within_printing("PRE 4") { assert_selector ".deck-card-qty", exact_text: "1" }
    within_printing("POR 56") { assert_selector ".deck-card-qty", exact_text: "1" }

    assert_no_selector "[data-action~='deck-rows#write']", visible: :all
    assert_no_selector ".qty-btn, .deck-printing-move, .deck-card-collect", visible: :all
    assert_no_selector ".deck-card-alloc, .deck-printing-owned", visible: :all
    assert_no_selector ".card-search-input", visible: :all
  end
end
