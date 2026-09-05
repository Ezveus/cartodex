require "application_system_test_case"

# The dashboard spotlight opens and closes its panel entirely client-side, so none of this is
# observable from a request test: the server answers the same frame either way.
class SpotlightSearchTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @deck = decks(:one)
    @deck.update!(user: @user, name: "Ogerpon Toolbox")
    # Pins the tournaments group as the last one in the panel, so "the last option" is a fixed
    # address rather than whatever the card fixtures happen to match.
    Tournament.create!(name: "Ogerpon Open", date: Date.new(2026, 4, 1),
                       format: "standard", standard_pool: standard_pools(:twm_por), tier: "league_cup",
                       created_by: @user)

    login_as @user, scope: :user
    visit dashboard_path
  end

  # Only an `input` event used to clear the dismissed flag, so a user who clicked away and clicked
  # back found the panel shut and the keys dead until they edited the query text.
  test "clicking away closes the panel and coming back reopens it" do
    search_for "Ogerpon"

    find("h1").click

    assert_no_selector ".spotlight-panel-open"

    find(".spotlight-input").click

    assert_selector ".spotlight-panel-open a[role=option]", text: "Ogerpon Toolbox"
  end

  test "the arrow keys move the highlight and say which row is selected" do
    search_for "Ogerpon"
    input = find(".spotlight-input")

    input.send_keys(:arrow_down)

    assert_selector "a[role=option][aria-selected=true]", count: 1
    assert_equal find("a[role=option][aria-selected=true]")[:id], input["aria-activedescendant"]
  end

  # The "see all" row is an option like any other, so the walk reaches it — it used to be a bare
  # link the keyboard skipped, and invalid inside a listbox besides.
  test "the walk reaches the see-all row and it leads to the filtered index" do
    search_for "Ogerpon"
    input = find(".spotlight-input")

    input.send_keys(:arrow_up) # from the initial state, ↑ lands on the last option of the list

    assert_selector "a.spotlight-see-all[aria-selected=true]"

    input.send_keys(:enter)

    # The archetype group is rendered last by Search::ResultsList, so its "see all" is the last
    # option. Naming that group here is what makes a reordering of the groups visible instead of
    # silent — this assertion followed the tournament group until the archetype one was appended.
    assert_current_path archetypes_path(q: "Ogerpon")
  end

  private

  # Types the query and waits for the debounced frame to land — asserting on the panel is what
  # proves the request came back, so a following assertion isn't racing it.
  def search_for(text)
    fill_in "Search decks, cards, tournaments and archetypes", with: text

    assert_selector ".spotlight-panel-open a[role=option]", text: "Ogerpon Toolbox"
  end
end
