require "test_helper"

module Decks
  class ResultRecorderTest < ActiveSupport::TestCase
    setup do
      @deck = users(:one).decks.create!(name: "Recorded", standard_pool: standard_pools(:twm_por))
      @deck.deck_cards.create!(card: cards(:honedge), quantity: 2)
    end

    test "records a result on the version the resolver answers" do
      outcome = ResultRecorder.call(deck: @deck, attributes: { result: "win" }, choice: nil)

      assert_empty outcome.errors
      assert outcome.result.persisted?
      assert_equal @deck.latest_version, outcome.result.deck_version
      assert_not_nil outcome.result.played_at
    end

    # The whole point of the service: a snapshot taken for a result that then fails validation
    # must not survive it.
    test "an invalid result on a deck with no version leaves no version behind" do
      outcome = nil
      assert_no_difference [ -> { DeckVersion.count }, -> { DeckVersionCard.count }, -> { DeckResult.count } ] do
        outcome = ResultRecorder.call(deck: @deck, attributes: { result: "win", match_format: "bo5" }, choice: nil)
      end

      assert_includes outcome.errors, "Match format is not included in the list"
    end

    test "an invalid result on a drifted deck asked for a new version leaves no version behind" do
      VersionSnapshot.call(@deck)
      @deck.deck_cards.create!(card: cards(:doublade), quantity: 1)

      assert_no_difference [ -> { DeckVersion.count }, -> { DeckResult.count } ] do
        ResultRecorder.call(deck: @deck.reload, attributes: { result: "win", match_format: "bo5" }, choice: "new")
      end
    end

    test "lets ChoiceRequired through for the caller to ask" do
      VersionSnapshot.call(@deck)
      @deck.deck_cards.create!(card: cards(:doublade), quantity: 1)

      assert_no_difference [ -> { DeckVersion.count }, -> { DeckResult.count } ] do
        assert_raises(VersionResolver::ChoiceRequired) do
          ResultRecorder.call(deck: @deck.reload, attributes: { result: "win" }, choice: nil)
        end
      end
    end
  end
end
