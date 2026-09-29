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

    # The participation of another deck is refused once, by the rule that says so. Resolving or
    # inheriting through it would file the result on that deck's version and add a second error
    # that only restates the first.
    test "a participation of another deck is refused with exactly the one error" do
      other = users(:one).decks.create!(name: "Other", standard_pool: standard_pools(:twm_por))
      entry = users(:one).tournament_entries.create!(tournament: tournaments(:two), deck: other,
        deck_version: VersionSnapshot.call(other))

      outcome = nil
      assert_no_difference [ -> { DeckResult.count }, -> { DeckVersion.count } ] do
        outcome = ResultRecorder.call(deck: @deck, attributes: { result: "win", tournament_entry_id: entry.id }, choice: nil)
      end

      assert_equal [ "Tournament entry must belong to the same deck" ], outcome.errors
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
