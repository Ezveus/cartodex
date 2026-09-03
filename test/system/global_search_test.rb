require "application_system_test_case"

# Opening, closing and focusing all happen client-side, so — like the dashboard spotlight's own
# test — none of it is observable from a request test.
class GlobalSearchTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @deck = decks(:one)
    @deck.update!(user: @user, name: "Ogerpon Toolbox")

    login_as @user, scope: :user
  end

  # The trigger sits in .navbar-inner rather than in .navbar-menu on purpose: below the
  # breakpoint the menu is display:none until the hamburger opens it, and a search you have to
  # unfold a menu to reach is not reachable "from any page". This test passing on the mobile half
  # of the sweep is what says so.
  test "the navbar trigger opens the overlay and a result navigates the whole page" do
    visit decks_path

    find(".navbar-search-trigger").click

    assert_selector "dialog.search-overlay[open]"

    fill_in "Search decks, cards and tournaments", with: "Ogerpon"

    assert_selector ".spotlight-panel-open a[role=option]", text: "Ogerpon Toolbox"
    find(".spotlight-panel-open a[role=option]", text: "Ogerpon Toolbox").click

    assert_current_path deck_path(@deck)
  end

  # The field's own Esc handler calls preventDefault, which kills the <dialog>'s native cancel —
  # so without the overlay listening for the bubbled event, Esc would empty the query and leave
  # the dialog open forever.
  test "escape empties the field and closes the overlay in one press" do
    visit decks_path
    find(".navbar-search-trigger").click
    fill_in "Search decks, cards and tournaments", with: "Ogerpon"

    assert_selector ".spotlight-panel-open a[role=option]", text: "Ogerpon Toolbox"

    find(".spotlight-input").send_keys(:escape)

    assert_no_selector "dialog.search-overlay[open]"
  end

  # "/" rather than ⌘K: the same handler, without a modifier to simulate.
  test "the slash shortcut opens the overlay and focuses its field" do
    visit decks_path

    find("body").send_keys("/")

    assert_selector "dialog.search-overlay[open]"
    assert_equal "search", evaluate_script("document.activeElement.type")
  end

  # The dashboard has no overlay to open — a second spotlight there would take the inline one's
  # Turbo frame — so the trigger focuses the field the page already shows.
  test "on the dashboard the trigger focuses the inline field" do
    visit dashboard_path

    assert_no_selector "dialog.search-overlay", visible: :all

    find(".navbar-search-trigger").click

    assert_equal "search", evaluate_script("document.activeElement.type")
  end
end
