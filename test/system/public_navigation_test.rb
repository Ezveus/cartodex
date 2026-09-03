require "application_system_test_case"

class PublicNavigationTest < ApplicationSystemTestCase
  test "a visitor can navigate from a shared deck" do
    deck = decks(:one)
    deck.update!(shared: true)

    visit deck_path(deck)
    assert_text deck.name

    # Not a plain click: below the breakpoint the menu is display:none until the hamburger
    # opens it, and this is the assertion that PublicNavbar really carries that hamburger.
    click_nav_link "Cards"

    assert_current_path cards_path
  end

  test "a visitor can page through the shared index and then open a deck" do
    # The pager lives inside a Turbo Frame and the deck rows have to escape it. Both halves
    # fail silently in a request test: the frame renders either way, and a link that navigates
    # the wrong target dies in the browser with "Content missing".
    (DecksController::SHARED_PER_PAGE + 1).times do |i|
      Deck.create!(user: users(:two), name: "Shared deck #{i}", shared: true, standard_pool: standard_pools(:twm_por))
    end

    visit shared_decks_path
    assert_text "Page 1 / 2"

    click_on "Next →"

    assert_text "Page 2 / 2"
    # turbo_action: "replace" — without it the frame swaps and the address bar does not.
    assert_current_path shared_decks_path(page: 2)

    click_on "Shared deck 0"

    assert_selector "h1", text: "Shared deck 0"
  end

  test "a signed-in user can reach the shared deck index from the navbar" do
    login_as users(:one), scope: :user

    visit dashboard_path
    click_nav_link "Shared decks"

    assert_current_path shared_decks_path
  end
end
