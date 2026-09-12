require "application_system_test_case"

# The scenario controls, in a browser, at both viewports. What is being asserted is that the numbers
# move *without a request*: the whole design rests on the curves being precomputed and shipped, and a
# version that quietly fetched per notch would pass every assertion about the values alone.
class DeckOddsTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    login_as @user, scope: :user
    @deck = @user.decks.create!(name: "Odds deck", standard_pool: standard_pools(:twm_por))
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 4)
    @deck.deck_cards.create!(card: cards(:teal_mask_ogerpon_ex), quantity: 4)
    @deck.deck_cards.create!(card: cards(:budew_asc), quantity: 4)
    @deck.deck_cards.create!(card: cards(:bosss_orders_meg), quantity: 4)
    @deck.deck_cards.create!(card: cards(:doublade), quantity: 4)
    # A one-of, and the only group on this deck whose prize curve is not 0.00 % at every point: four
    # copies are all-prized with probability 0.0004, which rounds to the same 0.00 % at every notch
    # of the stepper and makes the prize axis untestable. A single copy is 10.00 % at zero taken.
    @deck.deck_cards.create!(card: cards(:special_prism_energy_asc), quantity: 1)
    @deck.deck_cards.create!(card: cards(:basic_psychic_energy), quantity: 39)
  end

  # A thirteen-card deck is the one size where the turn control has no room: max_draws is 0 while
  # the field is still rendered min="1" max="1", because a max below its own min is not a control.
  # Clamping the turn against maxDrawsValue alone rewrote that field to 0 the moment Stimulus
  # connected — below its own min, so the browser marked it :invalid — while the numbers stayed
  # right, render() clamping the *sum* anyway. Only the control lied, which is why no assertion
  # about a percentage could have caught it.
  test "a deck with no draw pile keeps the turn control the server rendered" do
    small = @user.decks.create!(name: "Thirteen", standard_pool: standard_pools(:twm_por))
    small.deck_cards.create!(card: cards(:honedge), quantity: 4)
    small.deck_cards.create!(card: cards(:bosss_orders_meg), quantity: 9)

    visit odds_deck_path(small)
    assert_text "cards seen"

    turn = find("[data-deck-odds-target='turn']")
    assert_equal "1", turn.value
    assert_equal "1", turn[:min]
    assert_not page.evaluate_script("document.querySelector(\"[data-deck-odds-target='turn']\").validity.rangeUnderflow"),
      "Stimulus wrote the turn field below the min the server gave it"
    assert_text "7 cards seen (7 hand + 0 drawn + 0 prizes)"
  end

  # A flag on `window` is the probe: a full page load or a Turbo visit would clear it, so its survival
  # is what proves nothing went to the server.
  def mark_page
    page.execute_script("window.__oddsProbe = true")
  end

  def page_never_reloaded?
    page.evaluate_script("window.__oddsProbe === true")
  end

  # The expected value, read from the same service the page rendered from. Asserting only that the
  # number *changed* would pass on any change at all — including a wrong one — and would also fail
  # spuriously the day two rows happen to show the same percentage.
  def expected_seen(name, seen)
    row = Decks::Odds::Report.call(@deck.reload).card_rows.find { |r| r.name == name }
    format("%.2f %%", row.accessible_curve[seen])
  end

  def expected_prize(name, taken)
    row = Decks::Odds::Report.call(@deck.reload).card_rows.find { |r| r.name == name }
    format("%.2f %%", row.all_prized_curve[taken])
  end

  # Both panels hold a row for the same card, so an unscoped `.data-table-row` lookup is ambiguous
  # and raises. The panel is located through its own heading, the way page_view_test.rb does it.
  def panel(heading)
    find(:xpath, "//section[contains(concat(' ', normalize-space(@class), ' '), ' odds-panel ')]" \
                 "[./h2[normalize-space(.) = #{heading.inspect}]]")
  end

  def assert_seen(name, value)
    within(panel("By card")) do
      within(find(".data-table-row", text: name)) do
        assert_selector '[data-deck-odds-target="cell"]', exact_text: value
      end
    end
  end

  def assert_prized(name, value)
    within(panel("Prize risk")) do
      within(find(".data-table-row", text: name)) do
        assert_selector '[data-deck-odds-target="prizeCell"]', exact_text: value
      end
    end
  end

  def set_field(field, value)
    page.execute_script(<<~JS)
      const input = document.querySelector('[data-deck-odds-target="#{field}"]')
      input.value = "#{value}"
      input.dispatchEvent(new Event("input"))
    JS
  end

  test "the effect-draws stepper raises every accessibility number without a request" do
    visit odds_deck_path(@deck)

    # The page opens on turn 1, no effect draws, no prizes taken: a_rest = 1.
    assert_seen "Teal Mask Ogerpon ex", expected_seen("Teal Mask Ogerpon ex", 1)
    mark_page

    find('[aria-label="+ effect draws: one more"]').click

    assert_seen "Teal Mask Ogerpon ex", expected_seen("Teal Mask Ogerpon ex", 2)
    assert page_never_reloaded?, "the page reloaded — the curves are not being read client-side"
  end

  # The honest line: it is literally the number that enters the formula.
  test "the summary names the cards the scenario has seen" do
    visit odds_deck_path(@deck)

    assert_text "8 cards seen (7 hand + 1 drawn + 0 prizes)"

    3.times { find('[aria-label="Turn: one more"]').click }

    assert_text "11 cards seen (7 hand + 4 drawn + 0 prizes)"
  end

  # `d` and `p` enter the formula through their sum, so one notch of either moves an accessibility
  # cell by exactly the same amount — which is the property the two controls exist *despite*, and the
  # one a reader would never be shown otherwise.
  test "a prize taken and a card drawn move an accessibility cell identically" do
    visit odds_deck_path(@deck)

    find('[aria-label="+ effect draws: one more"]').click
    assert_seen "Budew", expected_seen("Budew", 2)

    find('[aria-label="+ effect draws: one less"]').click
    find('[aria-label="Prizes taken: one more"]').click

    assert_seen "Budew", expected_seen("Budew", 2)
  end

  # …and the prize columns are the exception, which is the other half of why the axes are two.
  test "the prize column reacts to prizes taken and not to draws" do
    visit odds_deck_path(@deck)

    assert_prized "Prism Energy", expected_prize("Prism Energy", 0)

    # Drawing cards does not change what is sitting in the prize block.
    5.times { find('[aria-label="+ effect draws: one more"]').click }

    assert_prized "Prism Energy", expected_prize("Prism Energy", 0)

    find('[aria-label="Prizes taken: one more"]').click

    assert_prized "Prism Energy", expected_prize("Prism Energy", 1)
  end

  # The ceilings are the deck's, not the JavaScript's. 47 draws is everything but the hand and the
  # prizes; a stepper that ran past it would index off the end of the curve and print "undefined %".
  test "the steppers clamp at this deck's own ceilings" do
    visit odds_deck_path(@deck)

    set_field("effectDraws", 9999)

    assert_equal "47", find('[data-deck-odds-target="effectDraws"]').value
    assert_text "54 cards seen (7 hand + 47 drawn + 0 prizes)"
    assert_no_text "undefined"
    assert_no_text "NaN"
  end

  # The two ceilings are different numbers, and only the prize axis can tell them apart: p <= 6 while
  # d <= N - 13. Clamped against the draw ceiling instead, every percentage on the page still prints
  # correctly — `#write` re-clamps a prize index to the end of its own seven-point curve — and only
  # the accessibility cells quietly run 41 notches too far, which no other test looks at.
  test "prizes taken clamps against the prize ceiling and not the draw one" do
    visit odds_deck_path(@deck)

    set_field("prizesTaken", 9999)

    assert_equal "6", find('[data-deck-odds-target="prizesTaken"]').value
    assert_text "14 cards seen (7 hand + 1 drawn + 6 prizes)"
    # One turn taken plus six prizes, never one turn plus the whole draw ceiling.
    assert_seen "Budew", expected_seen("Budew", 7)
  end
end
