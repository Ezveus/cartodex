require "application_system_test_case"
require_relative "../support/deck_card_rows"

# The set view's server rendering is held by the controller test of the same name (test/controllers/deck_set_grouping_test.rb). What only a browser sees: the
# heading count a stepper keeps true in place, and ⇄ moving a card from one set's section to
# another's in place, since the moved copy now belongs to another set.
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

    within(".deck-group-modes", text: "Group by") { click_on "Set" }

    assert_selector ".deck-set-section h2", text: "Ascended Heroes (ASC) · 1 card"
    assert_no_selector "h2", text: "Pokémon"
    assert_current_path deck_path(@deck, group: "set")

    within(".deck-group-modes", text: "Group by") { click_on "Type" }
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

    # The last copy takes its row with it, and the section it emptied.
    within_quantity_of("Budew") { click_on "-" }
    assert_no_selector ".deck-set-section[data-set-code='ASC']"
    assert_no_selector ".deck-sections [data-row-key]", text: "Budew"
    assert_selector por_heading, text: "Perfect Order (POR) · 2 cards"
    assert_equal "2", deck_total
  end

  # A card held in one printing changes printing from its own row, as it did with the printing
  # picker: expand, open "Other printings" (fetched), ⇄ — and the moved copy gets its set's section.
  test "a single-printing card changes printing from its set-view row" do
    meg = cards(:bosss_orders_meg)
    pal = cards(:trainer_card)
    pal.update_column(:fingerprint, meg.fingerprint)
    @deck.deck_cards.create!(card: meg, quantity: 3)

    visit deck_path(@deck, group: "set")
    assert_no_selector ".deck-set-section[data-set-code='PAL']"
    total = deck_total
    mark_page

    within(".deck-set-section[data-set-code='MEG']") do
      find(".deck-printings-toggle").click
      assert_selector "ul.deck-printing-list[data-deck-rows-pending]", visible: :all
      click_on "Other printings (1)"
      find("button.deck-printing-move[title='Move one copy here from MEG 114']").click
    end

    within(".deck-set-section[data-set-code='PAL']") do
      assert_selector "h2", exact_text: "PAL · 1 card"
      assert_selector "li[data-row-key='printing:#{pal.id}'] .deck-card-qty", exact_text: "1"
    end
    within(".deck-set-section[data-set-code='MEG']") do
      assert_selector "h2", text: "· 2 cards"
      assert_selector "li[data-row-key='printing:#{meg.id}'] > .deck-card-line .deck-card-qty", exact_text: "2"
    end
    assert_equal total, deck_total
    assert_page_not_reloaded
    assert_current_path deck_path(@deck, group: "set")

    rows = @deck.deck_cards.reload.index_by(&:card_id)
    assert_equal [ 2, 1 ], [ rows.fetch(meg.id).quantity, rows.fetch(pal.id).quantity ]
  end

  # A set-view row is one printing, so ⇄ is offered between the printings the deck holds. The copy
  # it moves lands in the other printing's section, and the one it empties goes.
  test "⇄ in the set view moves the copy into its set's section, in place" do
    @deck.deck_cards.create!(card: cards(:budew_pre), quantity: 1)

    visit decks_path
    visit deck_path(@deck, group: "set")
    assert_equal %w[POR ASC PRE], all(".deck-set-section").map { |s| s["data-set-code"] }
    mark_page

    within(".deck-set-section[data-set-code='PRE']") do
      find("button.deck-printing-move[title='Move one copy here from ASC 16']").click
    end

    within(".deck-set-section[data-set-code='PRE']") do
      assert_selector "h2", exact_text: "PRE · 2 cards"
      assert_selector ".deck-card-qty", exact_text: "2"
    end
    # The source printing emptied, and its section went with it.
    assert_no_selector ".deck-set-section[data-set-code='ASC']"
    assert_equal %w[POR PRE], all(".deck-set-section").map { |s| s["data-set-code"] }
    assert_equal "4", deck_total
    assert_page_not_reloaded
    assert_current_path deck_path(@deck, group: "set")

    # Nothing stacked on the history: back is the page before the deck.
    go_back
    assert_current_path decks_path
  end

  test "⇄ in the type view stays in place" do
    @deck.deck_cards.create!(card: cards(:budew_pre), quantity: 1)

    visit deck_path(@deck)
    mark_page

    expand_printings_of("Budew")
    within_printing("PRE 4") { find("button.deck-printing-move").click }

    within_printing("PRE 4") { assert_selector ".deck-card-qty", exact_text: "2" }
    # Checked after the move's own effect, so the request has landed; a reload would have dropped it.
    assert_page_not_reloaded
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
end

# The move used to reload the set view, and a reload lands at the top of the page, so on a deck
# taller than the window the moved row sat below the fold. In place, it stays on screen.
# A short window makes the three-card deck such a deck.
class DeckSetViewSwapScrollTest < ApplicationSystemTestCase
  include DeckCardRows

  drive_at 1400, 400

  setup do
    @user = users(:one)
    @deck = @user.decks.create!(name: "Set Watch", standard_pool: standard_pools(:twm_por))
    @deck.deck_cards.create!(card: cards(:budew_asc), quantity: 1)
    @deck.deck_cards.create!(card: cards(:budew_pre), quantity: 1)
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 2)
    login_as @user, scope: :user
  end

  test "⇄ in the set view leaves the page where the member was" do
    visit deck_path(@deck, group: "set")
    row = find(".deck-set-section[data-set-code='PRE'] li.deck-printing-row")
    page.execute_script("arguments[0].scrollIntoView({ block: 'center' })", row)
    # Not vacuous: at the top of the page the row is out of view.
    scrolled = page.evaluate_script("window.scrollY")
    assert_operator scrolled, :>, 0

    within(row) { find("button.deck-printing-move").click }

    within(".deck-set-section[data-set-code='PRE']") { assert_selector ".deck-card-qty", exact_text: "2" }
    # Not the same offset: the ASC section above it emptied and went, and the browser's scroll
    # anchoring keeps the row where it was on screen rather than the page where it was.
    assert_operator page.evaluate_script("window.scrollY"), :>, 0, "the page jumped to the top"
    pre_row = find(".deck-set-section[data-set-code='PRE'] li.deck-printing-row")
    top, bottom = page.evaluate_script(
      "(r => [r.top, r.bottom])(arguments[0].getBoundingClientRect())", pre_row
    )
    assert_operator top, :>=, 0
    assert_operator bottom, :<=, page.evaluate_script("window.innerHeight")
  end
end
