require "application_system_test_case"

# The admin navbar had no browser coverage at all: no system test visited the admin panel
# through it. That matters more than it sounds, because below 768px `.navbar-menu` is
# display:none until the `navbar` controller adds `.navbar-menu--open` — so a navbar missing
# the toggle, or wired to a different Stimulus controller, fails to navigate on the mobile half
# of the sweep and looks like a Capybara visibility bug rather than a missing button.
#
# Ui::NavbarShell exists to keep that markup in one place. This test is what lets the admin
# navbar be moved onto it without the move being invisible to the suite.
class AdminNavigationTest < ApplicationSystemTestCase
  setup do
    @admin = users(:one)
    @admin.update!(admin: true)
    login_as @admin, scope: :user
  end

  test "an admin can navigate the panel from its navbar on both sides of the breakpoint" do
    visit admin_root_path
    assert_selector ".navbar-brand", text: "Cartodex Admin"

    # Not a plain click: this is the assertion that the admin navbar really carries the
    # hamburger and the navbar controller that opens it.
    click_nav_link "Card Sets"
    assert_current_path admin_card_sets_path

    click_nav_link "Archetypes"
    assert_current_path admin_archetypes_path
  end

  test "the admin navbar keeps its way back to the app" do
    visit admin_root_path

    click_nav_link "Back to app"

    assert_current_path dashboard_path
  end
end
