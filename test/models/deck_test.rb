require "test_helper"

class DeckTest < ActiveSupport::TestCase
  test "has_many deck_results" do
    deck = decks(:one)
    assert_respond_to deck, :deck_results
  end

  test "destroying deck destroys deck_results" do
    deck = decks(:one)

    assert_difference "DeckResult.count", -deck.deck_results.count do
      deck.destroy
    end
  end
end
