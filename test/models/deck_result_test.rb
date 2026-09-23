require "test_helper"

class DeckResultTest < ActiveSupport::TestCase
  setup do
    @deck = decks(:one)
  end

  test "defaults to bo1 match format" do
    result = @deck.deck_results.create!(result: "win")
    assert_equal "bo1", result.match_format
  end

  test "requires a valid match format" do
    result = @deck.deck_results.new(result: "win", match_format: "bo5")
    assert_not result.valid?
    assert_includes result.errors[:match_format], "is not included in the list"
  end

  test "rejects a malformed score" do
    result = @deck.deck_results.new(result: "win", match_format: "bo3", score: "XY")
    assert_not result.valid?
    assert_includes result.errors[:score], "is invalid"
  end

  test "rejects a score on a bo1 match" do
    result = @deck.deck_results.new(result: "win", match_format: "bo1", score: "WW")
    assert_not result.valid?
    assert_includes result.errors[:score], "is only valid for best-of-three matches"
  end

  test "normalizes score to uppercase" do
    result = @deck.deck_results.create!(match_format: "bo3", score: "ww")
    assert_equal "WW", result.score
  end

  test "result_from_score maps games to the overall result" do
    assert_equal "win", DeckResult.result_from_score("WW")
    assert_equal "loss", DeckResult.result_from_score("LL")
    assert_equal "win", DeckResult.result_from_score("WLW")
    assert_equal "timeout", DeckResult.result_from_score("WLT")
    assert_equal "draw", DeckResult.result_from_score("WLD")
    assert_nil DeckResult.result_from_score("WL")
    assert_nil DeckResult.result_from_score("W")
  end

  test "derives the overall result from a bo3 score, overriding a conflicting value" do
    result = @deck.deck_results.create!(result: "loss", match_format: "bo3", score: "WW")
    assert_equal "win", result.result
  end

  test "keeps the manual result for a bo3 with no score" do
    result = @deck.deck_results.create!(result: "draw", match_format: "bo3")
    assert_equal "draw", result.result
    assert_nil result.score
  end

  # Recording a result counts as working on the deck for /decks' "most recently updated" order.
  test "recording, editing and deleting a result each move the deck's updated_at" do
    deck = decks(:one)
    deck.update_columns(updated_at: 3.days.ago)

    travel_to(2.days.ago) { @result = deck.deck_results.create!(result: "win") }
    assert_in_delta 2.days.ago, deck.reload.updated_at, 1.minute

    travel_to(1.day.ago) { @result.update!(result: "loss") }
    assert_in_delta 1.day.ago, deck.reload.updated_at, 1.minute

    @result.destroy!
    assert_in_delta Time.current, deck.reload.updated_at, 1.minute
  end
end
