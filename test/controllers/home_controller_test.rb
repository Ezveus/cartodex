require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    sign_in @user
  end

  test "dashboard renders the spotlight search" do
    get dashboard_path

    assert_response :success
    assert_select "form[action=?] input[name=q][role=combobox]", search_path
  end

  test "the spotlight form targets the results frame" do
    get dashboard_path

    assert_select "form[data-turbo-frame=search_results]"
  end

  test "the spotlight ships an empty results frame" do
    get dashboard_path

    assert_select "turbo-frame#search_results"
    assert_select "a[role=option]", count: 0
  end

  test "the combobox points at the frame it controls" do
    get dashboard_path

    assert_select "input[role=combobox][aria-controls=search_results][aria-expanded=false]"
  end

  test "the spotlight passes the service's minimum query length to Stimulus" do
    get dashboard_path

    assert_select "[data-dashboard-search-min-length-value=?]", Search::Global::MIN_QUERY_LENGTH.to_s
  end

  test "a visitor gets search, a showcase and a way in — and nothing personal" do
    sign_out @user
    shared = decks(:two)
    shared.update!(user: users(:two), shared: true, name: "Showcased")

    get dashboard_path

    assert_response :success
    assert_select ".spotlight"
    assert_select ".dashboard-showcase-deck-name", text: "Showcased"
    assert_select ".dashboard-showcase .badge-format"
    assert_select "a[href=?]", new_user_session_path
    assert_select ".dashboard-card", count: 0
    assert_select "#scanner-modal", count: 0
    assert_select "h1", text: /@/, count: 0
    # The decks Stimulus controller fetches /api/decks on connect; a visitor must not carry it.
    assert_select "[data-controller~=decks]", count: 0
  end

  test "the showcase never lists a private deck" do
    sign_out @user
    decks(:two).update!(user: users(:two), shared: false, name: "Private")

    get dashboard_path

    assert_select ".dashboard-showcase-deck-name", text: "Private", count: 0
  end

  test "root is the dashboard for everyone" do
    sign_out @user
    get root_path
    assert_response :success

    sign_in users(:one)
    get root_path
    assert_response :success
    assert_select ".dashboard-card"
  end
end
