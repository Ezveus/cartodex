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

  test "the first result on a deck with no version creates version 1 without asking" do
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 2)

    assert_difference -> { @deck.deck_versions.count }, 1 do
      post deck_results_path, params: { deck_result: { result: "win" } }, as: :json
    end

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal({ "number" => 1, "id" => @deck.latest_version.id }, json["deck_version"])
  end

  test "a drifted deck asks which version before writing anything" do
    drift_the_deck

    assert_no_difference [ -> { DeckResult.count }, -> { DeckVersion.count }, -> { DeckVersionCard.count } ] do
      post deck_results_path, params: { deck_result: { result: "win" } }, as: :json
    end

    assert_response :conflict
    assert_equal({ "error" => "version_choice_required", "current_version" => 1, "next_version" => 2,
                   "message" => "The list has changed since version 1." },
      JSON.parse(response.body))
  end

  test "current files the result on the existing version" do
    v1 = drift_the_deck

    assert_no_difference -> { DeckVersion.count } do
      post deck_results_path, params: { deck_result: { result: "win" }, version_choice: "current" }, as: :json
    end

    assert_response :created
    assert_equal v1, @deck.deck_results.last.deck_version
    assert_equal 1, JSON.parse(response.body).dig("deck_version", "number")
  end

  test "new snapshots version 2 and files the result on it" do
    drift_the_deck

    assert_difference -> { DeckVersion.count }, 1 do
      post deck_results_path, params: { deck_result: { result: "win" }, version_choice: "new" }, as: :json
    end

    assert_response :created
    assert_equal 2, JSON.parse(response.body).dig("deck_version", "number")
    assert_equal @deck.latest_version, @deck.deck_results.last.deck_version
  end

  test "new on an undrifted deck creates no version" do
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 2)
    v1 = Decks::VersionSnapshot.call(@deck)

    assert_no_difference -> { DeckVersion.count } do
      post deck_results_path, params: { deck_result: { result: "win" }, version_choice: "new" }, as: :json
    end

    assert_response :created
    assert_equal v1, @deck.deck_results.last.deck_version
  end

  test "an invalid result on a deck with no version leaves no version behind" do
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 2)

    assert_no_difference [ -> { DeckVersion.count }, -> { DeckResult.count } ] do
      post deck_results_path, params: { deck_result: { result: "win", match_format: "bo5" } }, as: :json
    end

    assert_response :unprocessable_entity
  end

  test "an invalid result on a drifted deck asked for a new version leaves no version behind" do
    drift_the_deck

    assert_no_difference [ -> { DeckVersion.count }, -> { DeckResult.count } ] do
      post deck_results_path,
        params: { deck_result: { result: "win", match_format: "bo5" }, version_choice: "new" }, as: :json
    end

    assert_response :unprocessable_entity
  end

  # A participation already says which list was played, so there is nothing to ask.
  test "a result attached to a participation takes its version without asking" do
    v1 = drift_the_deck
    entry = @user.tournament_entries.create!(tournament: tournaments(:two), deck: @deck, deck_version: v1)

    assert_no_difference -> { DeckVersion.count } do
      post deck_results_path, params: { deck_result: { result: "win", tournament_entry_id: entry.id } }, as: :json
    end

    assert_response :created
    assert_equal v1, @deck.deck_results.last.deck_version
  end

  private

  # A deck on v1 whose live list has since gained a card.
  def drift_the_deck
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 2)
    Decks::VersionSnapshot.call(@deck).tap do
      @deck.deck_cards.create!(card: cards(:doublade), quantity: 1)
    end
  end

  def deck_results_path
    "/api/decks/#{@deck.key}/results"
  end
end
