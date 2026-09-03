require "test_helper"

# The spotlight used to exist on the dashboard alone. These are the two server-side halves of
# making it reachable everywhere: the trigger is on every page, and no page ever carries two
# spotlights.
class GlobalSearchTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  # The trigger is the only route to the search on a page with no field of its own, so it has to
  # be everywhere — the two pages that *do* have a field included, where it focuses that field
  # rather than opening anything.
  test "every signed-in page carries the navbar search trigger" do
    sign_in users(:one)

    [ dashboard_path, decks_path, cards_path, collections_path, styleguide_path ].each do |path|
      get path

      assert_response :success
      assert_select ".navbar .navbar-search-trigger", 1, "no search trigger on #{path}"
    end
  end

  # /search is publicly reachable and the visitor dashboard already shows the spotlight, so the
  # visitor navbar gets the trigger on the same terms.
  test "a visitor gets the trigger too" do
    get cards_path

    assert_response :success
    assert_select ".navbar .navbar-search-trigger", 1
  end

  # CLAUDE.md: the styleguide is the living reference, and it renders the real components so it
  # cannot drift from what ships.
  test "the styleguide documents the trigger with the shipped component" do
    sign_in users(:one)

    get styleguide_path

    assert_select ".sg-search-trigger-demo .navbar-search-trigger", 1
  end

  # Search::ResultsView::FRAME_ID is a DOM id, and Turbo resolves a frame by id: a second
  # spotlight on the page would swallow the first one's results. That is the whole reason the
  # overlay is skipped on the pages that render their own field.
  test "no page carries two spotlights" do
    sign_in users(:one)

    [ dashboard_path, decks_path, styleguide_path ].each do |path|
      get path

      assert_select "##{Search::ResultsView::FRAME_ID}", 1, "duplicate search frame on #{path}"
      assert_select ".spotlight-input", 1, "duplicate spotlight input on #{path}"
    end
  end

  test "the overlay is rendered exactly on the pages that have no inline field" do
    sign_in users(:one)

    get decks_path
    assert_select "dialog.search-overlay", 1

    get dashboard_path
    assert_select "dialog.search-overlay", 0, "the dashboard's own field already answers the trigger"

    get styleguide_path
    assert_select "dialog.search-overlay", 0, "the styleguide renders a spotlight of its own"
  end
end
