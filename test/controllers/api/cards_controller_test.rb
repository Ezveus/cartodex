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

  # The 20 rows this endpoint returns used to be filtered down by its callers —
  # the archetype pickers asked only for Pokémon, then collapsed printings by
  # name — so the missing ORDER BY never showed. Now that a picker designates an
  # exact printing, every printing competes for those slots and rowid order would
  # decide which ones the user never sees.
  test "index orders by set release date, newest first, sets it does not know last" do
    # A third Budew, in POR (2026-01-16) — newer than budew_asc's ASC
    # (2025-11-07). budew_pre's PRE is not an imported set at all.
    Card.create!(name: "Budew", card_type: "Pokémon", card_set: card_sets(:por),
      set_name: "POR", set_number: "5", rarity: "Common",
      hp: 30, stage: "Basic", type_symbol: "Grass", retreat_cost: 1)

    get api_cards_path, params: { q: "budew" }, as: :json

    assert_response :success
    printings = JSON.parse(response.body).map { |c| [ c["set_name"], c["set_number"] ] }
    assert_equal [ [ "POR", "5" ], [ "ASC", "16" ], [ "PRE", "4" ] ], printings
  end

  test "index keeps a card whose set was never imported" do
    get api_cards_path, params: { q: "boss" }, as: :json

    assert_response :success
    # Neither Boss's Orders printing has a card_set; the LEFT JOIN must not drop them.
    printings = JSON.parse(response.body).map { |c| c["set_name"] }.sort
    assert_equal [ "MEG", "PAL" ], printings
  end

  test "index reports each card's type, now that types share one list" do
    get api_cards_path, params: { q: "budew asc" }, as: :json

    assert_response :success
    assert_equal "Pokémon", JSON.parse(response.body).first["card_type"]
  end

  test "index requires authentication" do
    sign_out @user
    get api_cards_path, params: { q: "budew" }, as: :json
    assert_response :unauthorized
  end
end
