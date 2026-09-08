require "application_system_test_case"

# Opening and closing a dropdown is entirely client-side, so none of it is observable from a
# request test.
#
# The fixture is deliberately the *existing* deck Actions dropdown (Decks::ActionsDropdown) rather
# than a purpose-built one: it declares no `trigger` target and takes the default open class, which
# is exactly the shape a hardcoded class name or an unguarded `triggerTarget` read would break —
# and Stimulus swallows a missing-target error into the console, so that break is silent.
class DropdownControllerTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @deck = decks(:one)
    @deck.update!(user: @user, name: "Ogerpon Toolbox")

    login_as @user, scope: :user
  end

  # Keys go to the trigger, which is *inside* the dropdown, so the outside-click handler cannot be
  # what closes it — this asserts about Escape and nothing else. It is also the case that goes red
  # if the aria write precedes the class removal: this caller has no trigger target, so a throw
  # there would leave the panel open with the error only in the console.
  test "escape closes a dropdown whose caller declares no trigger" do
    visit deck_path(@deck)

    actions_trigger.click

    assert_selector ".dropdown-menu--open"

    actions_trigger.send_keys(:escape)

    assert_no_selector ".dropdown-menu--open"
  end

  test "a click outside closes it" do
    visit deck_path(@deck)

    actions_trigger.click

    assert_selector ".dropdown-menu--open"

    # The deck title, not the stats below: the open panel hangs over everything under the actions
    # bar, and a click Chrome reports as intercepted is not a click outside.
    find("h1", text: @deck.name).click

    assert_no_selector ".dropdown-menu--open"
  end

  # The panel's usual exit is a click elsewhere, but "Edit" navigates from *inside* it — so the
  # outside-click handler never runs and the snapshot Turbo caches for the page left behind is
  # taken with the panel open. Restored, that panel floats over a page whose content has moved.
  # A restoration visit serves the cached snapshot without re-requesting, so nothing repaints it
  # away: closing before the snapshot is taken is the only thing that keeps Back usable.
  test "coming back to a cached page does not restore an open panel" do
    visit decks_path

    within "#deck-#{@deck.id}" do
      find(".dropdown button", text: "Actions").click

      assert_selector ".dropdown-menu--open"

      click_on "Edit"
    end

    assert_current_path edit_deck_path(@deck)

    page.go_back

    assert_current_path decks_path
    assert_no_selector ".dropdown-menu--open"
  end

  # This caller has no `trigger` target, so there is no element to carry aria-expanded and nothing
  # about the attribute can be asserted here — the point is the negative one: writing it must not
  # cost this caller the toggle. Both halves of the toggle running is what says the aria write did
  # not throw on the way past.
  test "a caller with no trigger target still toggles both ways" do
    visit deck_path(@deck)

    actions_trigger.click

    assert_selector ".dropdown-menu--open"

    actions_trigger.click

    assert_no_selector ".dropdown-menu--open"
  end

  private

  def actions_trigger
    find(".deck-actions-bar .dropdown button", text: "Actions")
  end
end

# Issue #105. Pinned to a width rather than to the mobile side of the sweep because the hamburger
# is `display: none` above the breakpoint: there is no button to click at all on the desktop half,
# and `drive_at` skips that half with a reason. 390 is the width MOBILE_SCREEN_SIZE asks for and
# cannot have — Chrome will not open a window below 500px — but drive_at goes through CDP, which
# is not subject to that floor.
class NavbarToggleAriaTest < ApplicationSystemTestCase
  drive_at 390, 844

  setup do
    login_as users(:one), scope: :user
  end

  test "the hamburger reports whether the menu is open" do
    visit decks_path

    assert_selector ".navbar-toggle[aria-expanded=false]"

    find(".navbar-toggle").click

    assert_selector ".navbar-toggle[aria-expanded=true]"

    find(".navbar-toggle").click

    assert_selector ".navbar-toggle[aria-expanded=false]"
  end
end
