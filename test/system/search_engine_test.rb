require "application_system_test_case"

# What a member meets of the browser search engine in a real browser: the one-time alert, which
# must outlive the five seconds other flashes get, and the page the engine opens.
class SearchEngineTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    decks(:one).update!(user: @user, name: "Ogerpon Toolbox")
    login_as @user, scope: :user
  end

  test "the announcement stays until dismissed and leads to the setup instructions" do
    @user.update_column(:search_engine_announced_at, nil)
    visit dashboard_path

    assert_selector "[data-testid=search-engine-announcement]"
    # Other flashes remove themselves after five seconds; this one carries a link.
    sleep 5.5
    assert_selector "[data-testid=search-engine-announcement]"

    click_on "Set it up in Settings"

    assert_selector "#search-engine h2", text: "Browser search engine"
    assert_selector "#search-engine-url", text: %r{/search\?q=%s\z}
    assert_no_selector "[data-testid=search-engine-announcement]", wait: 0
  end

  # The persistent value must default to false: every other flash still goes after five seconds.
  test "an ordinary flash still removes itself" do
    visit dashboard_path
    page.execute_script(<<~JS)
      const flash = document.createElement("div")
      flash.className = "flash flash-notice"
      flash.dataset.controller = "flash"
      flash.textContent = "Ordinary notice"
      document.getElementById("flash-messages").appendChild(flash)
    JS
    assert_selector ".flash-notice", text: "Ordinary notice"

    sleep 5.5
    assert_no_selector ".flash-notice", wait: 0
  end

  test "the announcement can be dismissed" do
    @user.update_column(:search_engine_announced_at, nil)
    visit dashboard_path

    within("[data-testid=search-engine-announcement]") { click_on "Dismiss" }

    assert_no_selector "[data-testid=search-engine-announcement]"
  end

  test "the page the engine opens lists the spotlight's results, and they navigate" do
    visit search_path(q: "ogerpon")

    within(".search-page-results") { click_on "Ogerpon Toolbox" }

    assert_current_path deck_path(decks(:one))
  end

  # The page carries the overlay too, so its frame id must not be taken by the page's own list.
  test "the spotlight still works from the search page" do
    visit search_path(q: "ogerpon")

    find(".navbar-search-trigger").click
    find(".spotlight-input").fill_in(with: "Toolbox")

    assert_selector ".spotlight-panel-open a[role=option]", text: "Ogerpon Toolbox"
  end
end
