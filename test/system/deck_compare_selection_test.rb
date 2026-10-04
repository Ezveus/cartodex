require "application_system_test_case"

# The compare selection lives in sessionStorage, so it follows the reader from one listing to
# another — which is what lets a member put somebody's shared deck beside one of their own.
# Nothing about it is visible to a request test: the server only ever sees the finished address.
class DeckCompareSelectionTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @mine = @user.decks.create!(name: "My Build", standard_pool: standard_pools(:twm_por))
    @theirs = users(:two).decks.create!(name: "Their Build", standard_pool: standard_pools(:twm_por), shared: true)

    @mine.deck_cards.create!(card: cards(:honedge), quantity: 2)
    @theirs.deck_cards.create!(card: cards(:honedge), quantity: 3)

    login_as @user, scope: :user
  end

  test "a deck picked on the shared listing is still picked on /decks, and both are compared" do
    visit shared_decks_path
    find(".deck-compare-checkbox[value='#{@theirs.key}']").check

    within(".deck-compare-bar") { assert_text "Their Build" }

    visit decks_path
    # Not on this listing, but still in the bar.
    within(".deck-compare-bar") { assert_text "Their Build" }
    find(".deck-compare-checkbox[value='#{@mine.key}']").check

    within(".deck-compare-bar") do
      assert_text "My Build"
      click_button "Compare"
    end

    assert_selector ".deck-compare-table thead th", text: "Their Build"
    assert_selector ".deck-compare-table thead th", text: "My Build"
    assert_selector ".deck-compare-card-row", text: "Honedge"
  end

  test "the shared deck page adds itself to the selection, and the bar removes it again" do
    visit deck_path(@theirs)
    click_button "Add to comparison"

    assert_button "Remove from comparison"
    within(".deck-compare-bar") do
      assert_text "1 selected"
      click_button "Remove Their Build from the comparison"
    end

    assert_button "Add to comparison"
    assert_no_selector ".deck-compare-bar.is-visible"
  end
end
