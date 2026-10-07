require "test_helper"

# The one-time "use Cartodex as a search engine" alert: shown on the first page a member actually
# sees, and claimed by that page only. See SearchEngineAnnouncementHost.
class SearchEngineAnnouncementTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  ANNOUNCEMENT = "[data-testid=search-engine-announcement]".freeze

  setup do
    @user = users(:one)
    @user.update_column(:search_engine_announced_at, nil)
    sign_in @user
  end

  test "the first page shows the alert, links to the settings section and records it" do
    get dashboard_path

    assert_response :success
    assert_select "#{ANNOUNCEMENT}.flash-info[data-flash-persistent-value=true]" do
      assert_select "a[href=?]", settings_path(anchor: "search-engine")
      assert_select "button.flash-close[data-action='flash#dismiss']"
    end
    assert_not_nil @user.reload.search_engine_announced_at
  end

  test "the next page does not show it again" do
    get dashboard_path
    get decks_path

    assert_response :success
    assert_select ANNOUNCEMENT, count: 0
  end

  # Turbo 8 prefetches a link on hover. That response is never shown unless the link is clicked,
  # so claiming the alert there would spend it on a page nobody saw.
  test "a hover prefetch neither shows nor spends it" do
    get decks_path, headers: { "X-Sec-Purpose" => "prefetch" }

    assert_response :success
    assert_select ANNOUNCEMENT, count: 0
    assert_nil @user.reload.search_engine_announced_at
  end

  # Chrome's own prefetch and prerender (the root, from the omnibox) say so with Sec-Purpose.
  test "a browser prefetch or prerender neither shows nor spends it" do
    [ "prefetch", "prefetch;prerender", "prerender;prefetch" ].each do |purpose|
      get dashboard_path, headers: { "Sec-Purpose" => purpose }

      assert_select ANNOUNCEMENT, count: 0
      assert_nil @user.reload.search_engine_announced_at, purpose
    end
  end

  test "a HEAD request does not spend it" do
    head dashboard_path

    assert_nil @user.reload.search_engine_announced_at
  end

  # A refused form re-renders the whole layout with a 422: an error page, not an announcement.
  test "a re-rendered form does not spend it" do
    post decks_path, params: { deck: { name: "" } }

    assert_response :unprocessable_content
    assert_select "nav.navbar"
    assert_nil @user.reload.search_engine_announced_at
  end

  # The layout renders whole for a frame request and Turbo keeps only the frame, so the alert
  # would land in markup that is thrown away.
  test "a Turbo Frame request neither shows nor spends it" do
    get search_path(q: "ogerpon"), headers: { "Turbo-Frame" => Search::ResultsView::FRAME_ID }
    get decks_path, headers: { "Turbo-Frame" => "decks" }

    assert_nil @user.reload.search_engine_announced_at
  end

  test "a member already announced does not see it" do
    @user.update_column(:search_engine_announced_at, 1.day.ago)

    get dashboard_path

    assert_select ANNOUNCEMENT, count: 0
  end

  test "a visitor never sees it" do
    sign_out @user

    get dashboard_path

    assert_response :success
    assert_select ANNOUNCEMENT, count: 0
  end

  test "an account created after the deploy is announced too" do
    sign_out @user
    newcomer = User.create!(email: "newcomer@example.com", password: "password123")
    sign_in newcomer

    get dashboard_path

    assert_select ANNOUNCEMENT, count: 1
  end

  test "the admin panel's layout shows it as well" do
    @user.update_column(:admin, true)

    get admin_root_path

    assert_response :success
    assert_select ANNOUNCEMENT, count: 1
  end

  # Layouts::ApplicationLayout has two hosts, and the consent screen's controller descends from
  # Doorkeeper's rather than ApplicationController: a helper missing there is a 500 on that page
  # and nowhere else.
  test "the OAuth consent screen renders it without error" do
    application = Doorkeeper::Application.create!(
      name: "Claude", redirect_uri: "https://claude.ai/api/mcp/auth_callback", scopes: "mcp:read mcp:write"
    )
    challenge = Base64.urlsafe_encode64(Digest::SHA256.digest("v" * 64), padding: false)

    get "/oauth/authorize", params: {
      client_id: application.uid, redirect_uri: application.redirect_uri, response_type: "code",
      scope: "mcp:read", code_challenge: challenge, code_challenge_method: "S256"
    }

    assert_response :success
    assert_select ANNOUNCEMENT, count: 1
  end
end
