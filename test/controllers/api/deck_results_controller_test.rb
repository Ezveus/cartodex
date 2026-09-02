require "test_helper"

class Api::DeckResultsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    sign_in @user
    @deck = @user.decks.create!(name: "My Deck", standard_pool: standard_pools(:twm_por))
  end

  test "create stores match format and derives result from a bo3 score" do
    post deck_results_path,
      params: { deck_result: { result: "loss", match_format: "bo3", score: "WW" } },
      as: :json

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal "win", json["result"]

    record = @deck.deck_results.last
    assert_equal "bo3", record.match_format
    assert_equal "WW", record.score
    assert_equal "win", record.result
  end

  test "create stores a bo1 result with no score" do
    post deck_results_path,
      params: { deck_result: { result: "win", match_format: "bo1" } },
      as: :json

    assert_response :created
    record = @deck.deck_results.last
    assert_equal "bo1", record.match_format
    assert_nil record.score
  end

  private

  def deck_results_path
    "/api/decks/#{@deck.key}/results"
  end
end
