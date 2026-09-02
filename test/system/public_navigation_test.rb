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

  test "a signed-in user can reach the shared deck index from the navbar" do
    login_as users(:one), scope: :user

    visit dashboard_path
    click_nav_link "Shared decks"

    assert_current_path shared_decks_path
  end
end
