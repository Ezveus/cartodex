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

    fill_in "Search decks, cards, tournaments and archetypes", with: "Ogerpon"

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
    fill_in "Search decks, cards, tournaments and archetypes", with: "Ogerpon"

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

  # The trigger is part of the search, not a click somewhere else in the page: the spotlight
  # watches the document for outside clicks, and the very click that opens the search bubbles up
  # to that watcher. Without the trigger being excluded there, clicking it collapsed the panel it
  # had just brought into focus and latched #dismissed, leaving the arrow keys and Enter dead
  # until the query text was edited.
  test "the trigger leaves results already on screen alone" do
    visit dashboard_path

    fill_in "Search decks, cards, tournaments and archetypes", with: "Ogerpon"

    assert_selector ".spotlight-panel-open a[role=option]", text: "Ogerpon Toolbox"

    find(".navbar-search-trigger").click

    assert_selector ".spotlight-panel-open a[role=option]", text: "Ogerpon Toolbox"

    find(".spotlight-input").send_keys(:down)

    assert_selector ".spotlight-input[aria-activedescendant]"
  end

  # The backdrop of a modal <dialog> is the dialog element itself, which is what clickBackdrop
  # keys on — so any padding the dialog carries of its own is a dismiss zone that looks like the
  # panel. The content wrapper is what keeps the visible ring around the field inert.
  test "a click on the overlay's own edge leaves it open" do
    visit decks_path
    find(".navbar-search-trigger").click
    fill_in "Search decks, cards, tournaments and archetypes", with: "Ogerpon"

    assert_selector ".spotlight-panel-open a[role=option]", text: "Ogerpon Toolbox"

    find("dialog.search-overlay").click(x: 8, y: 20, offset: :position)

    assert_selector "dialog.search-overlay[open]"
    assert_field "Search decks, cards, tournaments and archetypes", with: "Ogerpon"
  end

  # The overlay's whole point is navigating away from it, so the snapshot Turbo caches for the
  # page left behind is taken with the dialog open. Restored, that dialog is no longer modal: it
  # paints over the page with no backdrop, clicks outside it never reach clickBackdrop, and
  # open()'s "already open" guard declines to call showModal() — so the trigger cannot recover it
  # either. Closing it before the snapshot is taken is what keeps Back usable.
  test "coming back to a cached page does not restore the overlay" do
    visit decks_path
    find(".navbar-search-trigger").click
    fill_in "Search decks, cards, tournaments and archetypes", with: "Ogerpon"

    find(".spotlight-panel-open a[role=option]", text: "Ogerpon Toolbox").click

    assert_current_path deck_path(@deck)

    page.go_back

    assert_current_path decks_path
    assert_no_selector "dialog.search-overlay[open]"

    find(".navbar-search-trigger").click

    assert_selector "dialog.search-overlay[open]"
  end

  # The handler takes Ctrl+K as readily as ⌘K, so the hint must not promise a key the visitor's
  # keyboard does not have. Faked through CDP rather than asserted against the host running the
  # suite: on a Mac the Mac branch is the only one a real browser would ever take, and the branch
  # that was wrong is the other one.
  test "the hint names the modifier the platform actually has" do
    skip "faking the platform needs CDP, which the remote driver does not expose" unless cdp?

    as_platform("Win32", "Windows") do
      visit decks_path

      assert_selector ".navbar-search-trigger-hint", text: "Ctrl K", visible: :all
    end
  end

  # The styleguide renders the shipped trigger next to the navbar's own, which is the one page
  # where writing only the first hint target would leave a ⌘K on a PC.
  test "every hint on the page names that modifier, not just the first" do
    skip "faking the platform needs CDP, which the remote driver does not expose" unless cdp?

    as_platform("Win32", "Windows") do
      visit styleguide_path

      assert_selector ".navbar-search-trigger-hint", text: "Ctrl K", visible: :all, count: 2
    end
  end

  private

  # Chrome evaluates this before any of the page's own scripts, so the controller reads the faked
  # values on connect. Removed afterwards because the browser is shared by the whole run.
  def as_platform(platform, ua_data_platform)
    script = page.driver.browser.execute_cdp(
      "Page.addScriptToEvaluateOnNewDocument",
      source: <<~JS
        Object.defineProperty(navigator, "platform", { get: () => "#{platform}" });
        if (navigator.userAgentData) {
          Object.defineProperty(navigator, "userAgentData", {
            get: () => ({ platform: "#{ua_data_platform}" })
          });
        }
      JS
    )

    yield
  ensure
    page.driver.browser.execute_cdp("Page.removeScriptToEvaluateOnNewDocument", identifier: script["identifier"]) if script
  end
end

# Pinned to a desktop width because the assertion is about what the navbar does with its *free
# space*, and the signed-in navbar at this width has none — the member's links and email fill it.
# A visitor's navbar has room to spare, which is where two competing `margin-left: auto` were
# visible: they split that space instead of handing it to the trigger, parking the magnifier
# mid-navbar rather than beside the sign-in links.
class GlobalSearchNavbarLayoutTest < ApplicationSystemTestCase
  drive_at 1400, 900

  # The navbar's own `gap`, which is what separates the trigger from its neighbour once nothing
  # else claims the free space.
  NAVBAR_GAP = 32

  test "the trigger sits beside the links on the right rather than mid-navbar" do
    visit cards_path

    gap = evaluate_script(<<~JS)
      (() => {
        const trigger = document.querySelector(".navbar-search-trigger").getBoundingClientRect();
        const right = document.querySelector(".navbar-right").getBoundingClientRect();
        return Math.round(right.left - trigger.right);
      })()
    JS

    assert_equal NAVBAR_GAP, gap
  end
end
