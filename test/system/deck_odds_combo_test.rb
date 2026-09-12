require "application_system_test_case"

# The one control on the odds page that goes to the server, and the scenario controls still have to
# reach what comes back.
class DeckOddsComboTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    login_as @user, scope: :user
    @deck = @user.decks.create!(name: "Odds deck", standard_pool: standard_pools(:twm_por))
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 4)
    @deck.deck_cards.create!(card: cards(:teal_mask_ogerpon_ex), quantity: 4)
    @deck.deck_cards.create!(card: cards(:bosss_orders_meg), quantity: 4)
    @deck.deck_cards.create!(card: cards(:basic_psychic_energy), quantity: 48)
  end

  def frame = find("##{Decks::Odds::ComboFrame::FRAME_ID}")

  def picker = find("[data-deck-combo-target='picker']")

  # Every pick navigates the frame, and the next click lands on markup the response replaced. Waiting
  # for the chip is what makes the sequence a sequence rather than a race against Turbo.
  def pick(name)
    within(picker) { click_button name }
    within(frame) { assert_text name }
  end

  def add_to_group(index, name)
    find("[data-deck-combo-target='addCard'][data-deck-combo-index-param='#{index}']").click
    pick(name)
  end

  # "New group" opens the picker on a group that does not exist yet: an empty group cannot survive
  # the round trip, since the assignment travels as a URL and Decks::Odds::Combo refuses an empty
  # one. A group therefore exists from its first card.
  def add_to_new_group(name)
    click_button "New group"
    pick(name)
  end

  test "two groups are composed and answered" do
    visit odds_deck_path(@deck)

    add_to_group(0, "Honedge")
    add_to_new_group("Boss's Orders")

    within(frame) do
      assert_selector ".odds-combo-group", count: 2
      assert_text "Honedge"
      assert_text "Boss's Orders"
      assert_selector '[data-deck-odds-target="cell"]'
      assert_no_text "undefined"
    end
  end

  # The frame's answer ships its own curve, so the scenario controls keep moving it without a second
  # request — which is the whole reason the curve is in the response rather than a single number.
  test "the scenario controls move the combination's answer without another request" do
    visit odds_deck_path(@deck)

    add_to_group(0, "Honedge")
    add_to_new_group("Boss's Orders")

    report = Decks::Odds::Report.call(@deck.reload)
    combo = Decks::Odds::Combo.call(
      report: report,
      param: "#{Decks::Odds::Groups.key_for(cards(:honedge))}|" \
             "#{Decks::Odds::Groups.key_for(cards(:bosss_orders_meg))}"
    )
    combo_frame = frame

    within(combo_frame) do
      assert_selector '[data-deck-odds-target="cell"]', text: format("%.2f %%", combo.curve[1])
    end
    page.execute_script("window.__oddsProbe = true")

    3.times { find('[aria-label="+ effect draws: one more"]').click }

    within(combo_frame) do
      assert_selector '[data-deck-odds-target="cell"]', text: format("%.2f %%", combo.curve[4])
    end
    assert page.evaluate_script("window.__oddsProbe === true"),
      "the page reloaded — the frame curve is not being read client-side"
  end

  # The picker greys out a card already used elsewhere. That is a convenience and not the guarantee:
  # Decks::Odds::Combo re-checks it, because the param is a URL.
  test "a card already used cannot be picked into a second group" do
    visit odds_deck_path(@deck)

    add_to_group(0, "Honedge")
    click_button "New group"

    within(picker) do
      assert_button "Honedge", disabled: true
      assert_button "Boss's Orders", disabled: false
    end
  end

  # Fail closed, in a sentence, on a param no picker could have produced.
  test "a hand-written param naming a card twice is refused" do
    visit odds_deck_path(@deck, combo: "honedge_fp|honedge_fp")

    assert_text "A card can only be in one group."
    assert_no_selector "##{Decks::Odds::ComboFrame::FRAME_ID} [data-deck-odds-target='cell']"
  end

  test "a group can be emptied again" do
    visit odds_deck_path(@deck)

    add_to_group(0, "Honedge")

    click_button "Remove Honedge"

    within(frame) { assert_no_text "Honedge" }
  end
end
