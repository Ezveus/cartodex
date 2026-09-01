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
end
