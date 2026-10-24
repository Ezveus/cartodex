require "application_system_test_case"
require_relative "../support/deck_card_rows"

# ⇄ is the only place where a move's moving parts meet: the card's row rewritten in place around
# its printings, the printing it may empty and drop, the disclosures the member had open, and the
# deck-wide badge. A request test sees each response alone, so none of that is visible to one.
class DeckPrintingSwapTest < ApplicationSystemTestCase
  include DeckCardRows

  setup do
    # budew_pre and budew_asc share fingerprint "budew_shared" in fixtures.
    @user = users(:one)
    @asc = cards(:budew_asc)
    @pre = cards(:budew_pre)
    @deck = @user.decks.create!(name: "Printing Watch", physical: true, standard_pool: standard_pools(:twm_por))

    login_as @user, scope: :user
  end

  # The case the row was built for (#236): 3× Boss's Orders MEG 114, and the member wants one of
  # them to be the PAL 172 they do not own.
  test "⇄ splits three copies of one printing into two printings without a reload" do
    meg = cards(:bosss_orders_meg)
    pal = cards(:trainer_card)
    # Fixtures bypass compute_fingerprint, so the PAL printing has to be made one card with MEG's.
    pal.update_column(:fingerprint, meg.fingerprint)
    @user.collections.create!(card: meg, quantity: 3)
    @deck.deck_cards.create!(card: meg, quantity: 3, owned_copies: 3)

    visit deck_path(@deck)
    heading = ".deck-subsection[data-section-key='trainer-other'] h3"
    assert_selector heading, exact_text: "Other (3 — 1 unique)"
    assert_equal "3", deck_total
    mark_page

    expand_printings_of("Boss's Orders")
    # PAL 172 is not owned, so it waits behind "Other printings" rather than in the list itself.
    within(row_of("Boss's Orders")) { click_on "Other printings (1)" }
    within_printing("PAL 172") { find("button.deck-printing-move[title='Move one copy here from MEG 114']").click }

    within(row_of("Boss's Orders")) do
      assert_selector ".deck-card-total", exact_text: "3"
      assert_selector ".deck-card-alloc--summary .deck-card-alloc-label", exact_text: "2 real · 1 proxy"
      assert_selector ".deck-printing-row", count: 2
    end
    within_printing("MEG 114") do
      assert_selector ".deck-card-qty", exact_text: "2"
      assert_selector ".deck-card-alloc-label", exact_text: "2 real · 0 proxy"
    end
    within_printing("PAL 172") do
      assert_selector ".deck-card-qty", exact_text: "1"
      assert_selector ".deck-card-alloc-label", exact_text: "0 real · 1 proxy"
    end
    assert_selector heading, exact_text: "Other (3 — 1 unique)"
    assert_equal "3", deck_total
    assert_selector "turbo-frame#deck-header .badge-warning", text: "Proxies"
    assert_page_not_reloaded

    rows = @deck.deck_cards.reload.index_by(&:card_id)
    assert_equal [ 2, 2 ], rows.fetch(meg.id).values_at(:quantity, :owned_copies)
    assert_equal [ 1, 0 ], rows.fetch(pal.id).values_at(:quantity, :owned_copies)
  end

  test "⇄ onto a printing nobody owns keeps the backing of the copies left behind" do
    @user.collections.find_by!(card: @asc).update!(quantity: 2)
    @deck.deck_cards.create!(card: @asc, quantity: 3, owned_copies: 2)

    visit deck_path(@deck)
    assert_selector ".deck-card-alloc-label", exact_text: "2 real · 1 proxy"

    expand_printings_of("Budew")
    within(row_of("Budew")) { click_on "Other printings (1)" }
    within_printing("PRE 4") { find("button.deck-printing-move").click }

    within_printing("PRE 4") { assert_selector ".deck-card-alloc-label", exact_text: "0 real · 1 proxy" }
    # The proxy goes first on the source, so its two reals stay where they were.
    within_printing("ASC 16") { assert_selector ".deck-card-alloc-label", exact_text: "2 real · 0 proxy" }
    assert_selector "turbo-frame#deck-header .badge-warning", text: "Proxies"
  end

  test "⇄ that empties the source printing merges the card back into one row" do
    @deck.update!(physical: false)
    @deck.deck_cards.create!(card: @asc, quantity: 1)
    @deck.deck_cards.create!(card: @pre, quantity: 2)

    visit deck_path(@deck)
    # One card, whatever the number of printings: one row, and one unique.
    assert_selector ".deck-sections [data-row-key]", count: 1
    assert_selector "h2", text: "Pokémon (3 — 1 unique)"
    mark_page

    expand_printings_of("Budew")
    within_printing("PRE 4") { find("button.deck-printing-move[title='Move one copy here from ASC 16']").click }

    within(line_of("Budew")) do
      assert_selector ".deck-card-set", exact_text: "PRE 4"
      assert_selector ".deck-card-qty", exact_text: "3"
    end
    assert_no_selector ".deck-sections .deck-card-total"
    # ASC 16 is out of the deck and unowned: back behind "Other printings", in the list the member
    # had open, which the redraw keeps open.
    within(row_of("Budew")) { assert_button "Other printings (1)" }
    assert_no_selector ".deck-sections .deck-card-set", exact_text: "ASC 16"
    assert_selector "h2", text: "Pokémon (3 — 1 unique)"
    assert_page_not_reloaded

    rows = @deck.deck_cards.reload
    assert_equal [ @pre.id ], rows.map(&:card_id)
    assert_equal 3, rows.sole.quantity
  end

  # Every control in the redrawn row addresses its printing by card id. A stale one does not merely
  # 404: DeckCardQuantitySetter builds what it cannot find, so a stepper left pointing at the wrong
  # printing would silently create a row for it.
  test "the steppers of the printing a copy moved onto keep working, its reals re-derived" do
    @user.collections.find_by!(card: @pre).update!(quantity: 4)
    @deck.deck_cards.create!(card: @asc, quantity: 2)

    visit deck_path(@deck)
    expand_printings_of("Budew")
    # Owned, so it is offered in the list itself rather than behind "Other printings".
    within_printing("PRE 4") do
      assert_selector ".deck-printing-owned", exact_text: "4 owned · 4 free"
      find("button.deck-printing-move").click
    end
    # Landing on an owned printing claims a real copy, the way a quantity + does.
    within_printing("PRE 4") { assert_selector ".deck-card-alloc-label", exact_text: "1 real · 0 proxy" }

    within_printing("PRE 4") { within(".deck-card-qty-controls") { click_on "+" } }
    within_printing("PRE 4") do
      assert_selector ".deck-card-qty", exact_text: "2"
      assert_selector ".deck-card-alloc-label", exact_text: "2 real · 0 proxy"
    end

    within_printing("PRE 4") { within(".deck-card-alloc") { click_on "−" } }
    within_printing("PRE 4") { assert_selector ".deck-card-alloc-label", exact_text: "1 real · 1 proxy" }
    within(row_of("Budew")) { assert_selector ".deck-card-total", exact_text: "3" }

    rows = @deck.deck_cards.reload.index_by(&:card_id)
    assert_equal [ @asc.id, @pre.id ].sort, rows.keys.sort, "no row was created for another printing"
    assert_equal [ 1, 0 ], rows.fetch(@asc.id).values_at(:quantity, :owned_copies)
    assert_equal [ 2, 1 ], rows.fetch(@pre.id).values_at(:quantity, :owned_copies)
  end

  # The disclosure is a native button, so the keyboard opens it with no handler of its own — and
  # the ⇄ it reveals is reachable and labelled with the printing it takes the copy from.
  test "the printings open from the keyboard and ⇄ names its source" do
    @deck.deck_cards.create!(card: @asc, quantity: 1)

    visit deck_path(@deck)
    within(line_of("Budew")) { find(".deck-printings-toggle").send_keys(:enter) }

    within(row_of("Budew")) do
      assert_selector ".deck-printings-toggle[aria-expanded='true']"
      find(".deck-printings-others-toggle").send_keys(:enter)
      assert_selector "button.deck-printing-move[aria-label='Move one copy here from ASC 16']"
    end
    assert_equal [ @asc.id ], @deck.deck_cards.reload.map(&:card_id), "opening moved nothing"
  end

  test "a card with no other printing on record offers neither the printings nor ⇄" do
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 1)

    visit deck_path(@deck)

    within(line_of("Honedge")) { assert_selector ".deck-card-set", exact_text: "POR 56" }
    within(row_of("Honedge")) do
      assert_no_selector ".deck-printings-toggle", visible: :all
      assert_no_selector ".deck-printing-move", visible: :all
    end
  end
  # The public page may not read `card_sets`, so it lists a card's printings by set code where the
  # owner's follows the catalogue, newest set first: POR (2026-01-16) is newer than ASC while "ASC"
  # sorts first. POR is added first, so neither order is the rows' own.
  test "a visitor reads a card's printings by set code, the owner by release" do
    por = Card.create!(name: @asc.name, card_type: "Pokémon", hp: @asc.hp, type_symbol: @asc.type_symbol,
                       retreat_cost: @asc.retreat_cost, stage: @asc.stage, card_set: card_sets(:por),
                       set_name: "POR", set_number: "3", rarity: "Common")
    por.update_column(:fingerprint, @asc.fingerprint)
    @deck.deck_cards.create!(card: por, quantity: 2)
    @deck.deck_cards.create!(card: @asc, quantity: 1)
    @deck.update!(shared: true)

    visit deck_path(@deck)
    expand_printings_of("Budew")
    assert_equal [ "POR 3", "ASC 16" ], visible_printings

    logout(:user)
    visit deck_path(@deck)
    within(line_of("Budew")) { click_on "2 printings" }
    assert_equal [ "ASC 16", "POR 3" ], visible_printings
  end

  def visible_printings
    find("#deck-printings-budew_shared", visible: true)
      .all(":scope > li.deck-printing-row .deck-card-set").map(&:text)
  end
end
