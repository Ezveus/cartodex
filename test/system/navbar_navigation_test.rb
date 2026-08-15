require "application_system_test_case"

# Navigating through the navbar is the one interaction that genuinely differs across the breakpoint,
# rather than merely looking different. Below 768px `.navbar-menu` is `display: none` until the
# hamburger toggles `.navbar-menu--open` onto it, and Capybara will not click what it cannot see —
# so a test that clicks a nav link directly passes on the desktop half of the sweep and fails on the
# mobile one, for a reason that has nothing to do with what it was testing.
#
# `click_nav_link` absorbs that difference, and this class is what proves it absorbs it. Every
# assertion here is identical on both sides; only the path the helper takes to satisfy it changes.
class NavbarNavigationTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    login_as @user, scope: :user
  end

  test "a navbar link reaches its page" do
    visit dashboard_path

    click_nav_link "Decks"

    assert_selector "h1", text: "My Decks"
    assert_current_path decks_path
  end

  # The helper has to cope with the menu already being open — on the mobile half a second navigation
  # within one test would otherwise click the hamburger shut again and then fail to find the link.
  test "a second navbar link reaches its page too" do
    visit dashboard_path

    click_nav_link "Decks"
    click_nav_link "Collection"

    assert_current_path collections_path
  end
end
