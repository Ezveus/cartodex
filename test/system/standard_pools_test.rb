require "application_system_test_case"

# The three things about the Standard anchor that only a browser can see: the picker is conditional
# on the format (a Stimulus toggle over an inline style written server-side), the pool the user
# picks reaches the deck's badge, and a deck left on an older Standard is told so.
class StandardPoolsTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    login_as @user, scope: :user
  end

  # The form pre-selects StandardPool.current (twm_por), so picking twm_asc is a real change and the
  # badge naming it proves the submitted value reached the deck rather than the default surviving.
  test "picking a Standard when creating a deck shows it on the badge" do
    visit new_deck_path

    fill_in "Name", with: "Anchored deck"
    select "TWM-ASC", from: "deck_standard_pool_id"
    click_on "Create Deck"

    assert_selector ".badge.badge-format", text: "Standard (TWM-ASC)"
  end

  # The picker is conditional: the eternal formats have no pool. `visible: :hidden` rather than the
  # `visible: false` that reads like it — Capybara maps `false` to `:all`, which matches whatever the
  # visibility, so that assertion would pass with the toggle ripped out. It also asserts more than
  # `assert_no_selector` would: the field is hidden, not gone.
  test "the Standard picker disappears when the format is not Standard" do
    visit new_deck_path

    assert_selector "#deck_standard_pool_id", visible: :visible

    select "GLC", from: "deck_format"

    assert_selector "#deck_standard_pool_id", visible: :hidden

    # Back again: the toggle has to restore the field, not merely be able to hide it once.
    select "Standard", from: "deck_format"

    assert_selector "#deck_standard_pool_id", visible: :visible
  end

  # The classification form — and so the notice inside it — is rendered only by DecksController#edit,
  # which sets @editing and re-renders :show. deck_path never reaches it.
  test "a deck anchored to an older Standard is invited to update" do
    deck = decks(:one)
    deck.update!(format: "standard", standard_pool: standard_pools(:twm_asc))

    visit edit_deck_path(deck)

    # Scoped to the notice: both pool names also appear in the select's own options, so an unscoped
    # assertion would pass with no notice rendered at all.
    within ".standard-pool-notice" do
      assert_text "TWM-ASC" # the anchor it is on
      assert_text "TWM-POR" # the pool it is invited to move to
    end
  end

  # The other half of the same rule: a deck already on the current pool must not be nagged.
  test "a deck on the current Standard gets no notice" do
    deck = decks(:one)
    deck.update!(format: "standard", standard_pool: standard_pools(:twm_por))

    visit edit_deck_path(deck)

    assert_selector "#deck_standard_pool_id" # the form did render
    assert_no_selector ".standard-pool-notice"
  end
  # The tournament form's pool select follows its date field. Before this, the server pre-selected
  # the pool for the date the form was first rendered with — today, on a new tournament — and it
  # kept saying that after the user changed the date to a past event, so recording last month's
  # tournament silently anchored it to the current Standard. `has_select?` waits, which is what
  # makes this a test of the Stimulus controller rather than a race against it.
  test "the tournament pool follows the date" do
    visit new_tournament_path

    # 2026-09-01 is after twm_por became legal (2026-01-30), so the server pre-selects it.
    assert page.has_select?("tournament_standard_pool_id", selected: "TWM-POR")

    # A Date, not a String: typed into a type=date input, "2025-12-01" is consumed segment by
    # segment in the browser's own locale and lands as garbage (51201-02-20, measured). Capybara
    # formats a Date object for the field instead.
    #
    # 2025-12-01 is after twm_asc became legal (2025-11-21) and before twm_por did.
    fill_in "Date", with: Date.new(2025, 12, 1)

    assert page.has_select?("tournament_standard_pool_id", selected: "TWM-ASC")
  end

  # An explicit choice outranks the date: the controller stops following once the user has picked,
  # so a later date edit cannot quietly undo their pick.
  test "a hand-picked tournament pool survives a later date change" do
    visit new_tournament_path

    select "TWM-ASC", from: "tournament_standard_pool_id"
    fill_in "Date", with: Date.new(2026, 8, 1) # a date whose own pool would be TWM-POR

    assert page.has_select?("tournament_standard_pool_id", selected: "TWM-ASC")
  end
end
