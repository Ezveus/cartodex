require "application_system_test_case"

# Locks down the click-through contract of the decks index after the search field
# has swapped the deck_results Turbo Frame.
#
# The regression this covers: the debounced filter form targets the frame, so every
# link rendered inside it is frame-scoped by default. Without
# data-turbo-frame="_top" a click replaced the grid with Turbo's "Content missing"
# error and the URL never changed — invisible to request tests, which only ever see
# one response at a time.
class DeckSearchTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @deck = decks(:one)
    @deck.update!(user: @user, name: "Charizard Pidgeot", description: "Fire box")
    @other = decks(:two)
    @other.update!(user: @user, name: "Gardevoir Munkidori")

    login_as @user, scope: :user
  end

  test "filtering the grid then clicking a deck lands on that deck's page" do
    filter_to_charizard

    click_on "Charizard Pidgeot"

    assert_current_path deck_path(@deck)
    assert_selector "h1", text: "Charizard Pidgeot"
  end

  test "filtering the grid then clicking Edit lands on that deck's edit page" do
    filter_to_charizard

    within "#deck-#{@deck.id}" do
      click_on "Actions ▾"
      click_on "Edit"
    end

    assert_current_path edit_deck_path(@deck)
  end

  # The filter bar sits outside deck_results, so the server renders its "Clear" link once and
  # never again — only the browser can keep it in step with what is actually in the fields.
  test "the Clear link follows the query as it is typed and emptied" do
    visit decks_path

    assert_no_selector "form.deck-filters a", text: "Clear"

    fill_in "Search decks", with: "Charizard"

    assert_selector "form.deck-filters a", text: "Clear"

    fill_in "Search decks", with: ""

    assert_no_selector "form.deck-filters a", text: "Clear"
  end

  private

  # Types into the search field and waits for the frame to swap. Asserting the
  # filtered-out deck is *gone* is what proves the swap happened: the assertion
  # that follows would otherwise be testing an unfiltered, never-swapped frame.
  def filter_to_charizard
    visit decks_path

    assert_selector "turbo-frame#deck_results #deck-#{@other.id}"

    fill_in "Search decks", with: "Charizard"

    assert_no_selector "turbo-frame#deck_results #deck-#{@other.id}"
    assert_selector "turbo-frame#deck_results #deck-#{@deck.id}"
  end
end
