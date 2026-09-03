require "application_system_test_case"

class TournamentCatalogTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    login_as @user, scope: :user
  end

  test "a member searches the catalog, catalogues the missing event, and records a participation" do
    visit dashboard_path
    click_nav_link "Tournaments"

    fill_in "Search tournaments", with: "toulouse"
    assert_text "No tournaments match this search"

    click_on "Add a tournament"
    fill_in "Name", with: "League Cup Toulouse"
    # A Date, not a String: typed into a type=date input, "2026-04-11" is consumed segment by
    # segment in the browser's own locale and lands as garbage (51201-02-20, measured — see
    # test/system/standard_pools_test.rb). Capybara formats a Date object for the field.
    fill_in "Date", with: Date.new(2026, 4, 11)
    select "League Cup", from: "Tournament tier"
    click_on "Create Tournament"

    # Cataloguing an event lands on the participation form: that redirect is the whole reason
    # the two forms are chained rather than combined.
    assert_selector "h1", text: "Record your participation"
    select decks(:one).name, from: "Deck"
    fill_in "Number of participants", with: "24"
    fill_in "Final placement", with: "3"
    click_on "Create Tournament entry"

    assert_selector "h1", text: "League Cup Toulouse"
    assert_text "#3 / 24"

    click_nav_link "My tournaments"
    assert_text "League Cup Toulouse"
  end

  test "the catalog refuses a duplicate and points at the event already there" do
    visit new_tournament_path

    fill_in "Name", with: tournaments(:one).name.upcase
    fill_in "Date", with: tournaments(:one).date
    click_on "Create Tournament"

    assert_text "already catalogued"
    click_on tournaments(:one).name

    assert_selector "h1", text: tournaments(:one).name
  end
end
