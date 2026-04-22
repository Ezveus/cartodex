require "test_helper"

class Api::CardsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    sign_in @user
  end

  test "index with short query returns nothing" do
    get api_cards_path, params: { q: "a" }, as: :json
    assert_response :success
    assert_equal [], JSON.parse(response.body)
  end

  test "index searches by name substring" do
    get api_cards_path, params: { q: "bude" }, as: :json
    assert_response :success
    names = JSON.parse(response.body).map { |c| c["name"] }
    assert_includes names, "Budew"
  end

  test "index narrows by set code when query includes a known code" do
    get api_cards_path, params: { q: "budew asc" }, as: :json
    assert_response :success
    results = JSON.parse(response.body)
    assert_equal 1, results.length
    assert_equal "Budew", results[0]["name"]
    assert_equal "ASC", results[0]["set_name"]
  end

  test "index narrows by set code and set number" do
    get api_cards_path, params: { q: "honedge por 56" }, as: :json
    assert_response :success
    results = JSON.parse(response.body)
    assert_equal 1, results.length
    assert_equal "Honedge", results[0]["name"]
    assert_equal "56", results[0]["set_number"]
  end

  test "index narrows by set number alone" do
    get api_cards_path, params: { q: "budew 16" }, as: :json
    assert_response :success
    results = JSON.parse(response.body)
    assert_equal 1, results.length
    assert_equal "16", results[0]["set_number"]
  end

  test "index does not treat unknown trailing short word as a set code" do
    get api_cards_path, params: { q: "boss ex" }, as: :json
    assert_response :success
    # "ex" is not a known set code, so it should be treated as part of the name
    # (no cards named "Boss ex" exist in fixtures, so result is empty)
    assert_equal [], JSON.parse(response.body)
  end

  test "index requires authentication" do
    sign_out @user
    get api_cards_path, params: { q: "budew" }, as: :json
    assert_response :unauthorized
  end
end
