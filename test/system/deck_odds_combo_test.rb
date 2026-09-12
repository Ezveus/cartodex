require "application_system_test_case"
require "net/http"

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

  # The only refusal on this page that is a property of the reader's minute rather than of the deck,
  # and the only one the server cannot put on the screen itself: past the ration Rails answers 429
  # with no body at all in production, so Turbo's frame loader stops at a falsy responseHTML — it
  # replaces nothing and dispatches no turbo:frame-missing either. Before the notice this test pins,
  # a pick simply did nothing, with no trace anywhere but the network tab.
  #
  # Signed out on purpose: `unless: -> { user_signed_in? }` means the ration exists for nobody else,
  # so a test that stayed logged in would assert about a limiter that never runs.
  test "a pick refused by the ration says so, and the next one is sent" do
    # The budget is keyed on the client's IP. The burn below comes from this process, which is the
    # browser's own host only when Chrome is local — in the devcontainer it is another container,
    # with another address, and the budget this test spends is not the one the browser holds.
    skip "the browser is remote, so its IP is not this process's" if ENV["CAPYBARA_SERVER_PORT"]

    logout
    @deck.update!(shared: true)

    with_real_rate_limit_store do
      visit odds_deck_path(@deck)
      add_to_group(0, "Honedge")

      burn_odds_budget
      find("[data-deck-combo-target='addCard'][data-deck-combo-index-param='0']").click
      within(picker) { click_button "Boss's Orders" }

      assert_text "That combination was not sent"
      # The composition the refused click was made against is still standing: the notice lives
      # outside the frame, and the frame was never replaced.
      within(frame) { assert_text "Honedge" }
      assert_no_selector "[data-deck-combo-target='picker']", visible: true
    end

    # …and the refusal is not permanent. Outside the block the store is the :null_store again and
    # the limiter is a no-op, so the very same pick — the same `src`, which is what makes this the
    # interesting half — has to reach the server and answer, and the notice has to go away with it.
    add_to_group(0, "Boss's Orders")

    within(frame) { assert_text "Boss's Orders" }
    assert_no_text "That combination was not sent"
  end

  private

  # Spends the whole per-minute ration from this process, so that the browser's next pick is refused.
  # More requests than the limit rather than exactly the remainder: every one past it is answered
  # 429 and costs nothing, and counting the page load and the picks against the budget by hand is
  # the kind of arithmetic that goes stale the first time a test above adds a click.
  def burn_odds_budget
    uri = URI.join(page.server.base_url, odds_deck_path(@deck))

    DecksController::ODDS_RATE_LIMIT_TO.times { Net::HTTP.get_response(uri) }
  end

  # The seventh copy of this helper in the suite, mirroring test/controllers/decks_rate_limit_test.rb:
  # the test environment's cache store is :null_store, which makes `rate_limit` a no-op, so a real
  # store has to stand in. Here it is the *server's* cache that has to change, which works only
  # because the Capybara server runs in this process.
  def with_real_rate_limit_store
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    yield
  ensure
    Rails.cache = original_cache
  end
end
