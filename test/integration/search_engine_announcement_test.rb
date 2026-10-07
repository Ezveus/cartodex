require "test_helper"

# The one-time "use Cartodex as a search engine" alert. Rendering shows it and never spends it;
# the alert spends it itself, from the browser, once it is on screen (announcement_controller.js).
# See User#acknowledge_search_engine_announcement!.
class SearchEngineAnnouncementTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  ANNOUNCEMENT = "[data-testid=search-engine-announcement]".freeze

  setup do
    @user = users(:one)
    @user.update_column(:search_engine_announced_at, nil)
    sign_in @user
  end

  test "a pending member's page shows the alert, wired to acknowledge itself" do
    get dashboard_path

    assert_response :success
    assert_select "#{ANNOUNCEMENT}.flash-info[data-flash-persistent-value=true][data-turbo-temporary]" do |alert|
      assert_equal "flash announcement", alert.first["data-controller"]
      assert_equal search_engine_announcement_path, alert.first["data-announcement-url-value"]
      assert_select "a[href=?]", settings_path(anchor: "search-engine")
      assert_select "button.flash-close[data-action='flash#dismiss']"
    end
  end

  # Turbo prefetches on hover, keeps only the frame of a frame request and discards a whole
  # response to reload the page after a deploy changed a tracked asset: a rendered page is not a
  # seen page, so no rendering may spend the announcement.
  test "rendering never spends it, whatever kind of request rendered" do
    get dashboard_path
    get decks_path, headers: { "X-Sec-Purpose" => "prefetch" }
    get decks_path, headers: { "Sec-Purpose" => "prefetch;prerender" }
    get decks_path, headers: { "Turbo-Frame" => "decks" }
    head dashboard_path

    assert_nil @user.reload.search_engine_announced_at
    get decks_path
    assert_select ANNOUNCEMENT, count: 1, msg: "still pending, so still shown"
  end

  test "the acknowledgement records it, and the alert is gone from then on" do
    delete search_engine_announcement_path

    assert_response :no_content
    assert_not_nil @user.reload.search_engine_announced_at

    get dashboard_path
    assert_select ANNOUNCEMENT, count: 0
  end

  test "a second acknowledgement writes nothing" do
    delete search_engine_announcement_path
    first = @user.reload.search_engine_announced_at

    travel 1.hour do
      delete search_engine_announcement_path
    end

    assert_response :no_content
    assert_equal first, @user.reload.search_engine_announced_at
  end

  test "the acknowledgement needs a session" do
    sign_out @user

    delete search_engine_announcement_path

    assert_redirected_to new_user_session_path
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
  # Doorkeeper's rather than ApplicationController: anything the alert needs that only the first
  # host provides is a 500 on that page and nowhere else.
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
