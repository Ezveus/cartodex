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
end
