require "test_helper"

module Decks
  class VersionResolverTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      @deck = @user.decks.create!(name: "Resolved", standard_pool: standard_pools(:twm_por))
      @deck.deck_cards.create!(card: cards(:honedge), quantity: 2)
    end

    test "a deck with no version gets version 1 silently, whatever the choice" do
      version = nil
      assert_difference -> { DeckVersion.count }, 1 do
        version = VersionResolver.call(deck: @deck, choice: nil)
      end

      assert_equal 1, version.number
    end

    test "an undrifted deck answers its latest version, even when asked for a new one" do
      v1 = VersionSnapshot.call(@deck)

      assert_no_difference -> { DeckVersion.count } do
        assert_equal v1, VersionResolver.call(deck: @deck.reload, choice: "new")
      end
    end

    test "a drifted deck with no choice raises, naming both numbers, and writes nothing" do
      VersionSnapshot.call(@deck)
      @deck.deck_cards.create!(card: cards(:doublade), quantity: 1)

      error = assert_no_difference -> { DeckVersion.count } do
        assert_raises(VersionResolver::ChoiceRequired) { VersionResolver.call(deck: @deck.reload, choice: nil) }
      end

      assert_equal 1, error.current_number
      assert_equal 2, error.next_number
      assert_equal "The list has changed since version 1.", error.message
    end

    test "the question names what changed" do
      VersionSnapshot.call(@deck)
      @deck.update!(standard_pool: standard_pools(:twm_asc))

      error = assert_raises(VersionResolver::ChoiceRequired) { VersionResolver.call(deck: @deck.reload, choice: nil) }

      assert_equal "The Standard pool has changed since version 1 (TWM-POR → TWM-ASC).", error.message
    end

    test "a drifted deck answers the latest on current and a snapshot on new" do
      v1 = VersionSnapshot.call(@deck)
      @deck.deck_cards.create!(card: cards(:doublade), quantity: 1)

      assert_equal v1, VersionResolver.call(deck: @deck.reload, choice: "current")

      v2 = VersionResolver.call(deck: @deck.reload, choice: "new")
      assert_not_equal v1, v2
      assert_equal 2, v2.number
    end

    test "an entry's version wins over the deck's state and the choice" do
      v1 = VersionSnapshot.call(@deck)
      entry = @user.tournament_entries.create!(tournament: tournaments(:two), deck: @deck, deck_version: v1)
      @deck.deck_cards.create!(card: cards(:doublade), quantity: 1)

      assert_no_difference -> { DeckVersion.count } do
        assert_equal v1, VersionResolver.call(deck: @deck.reload, choice: "new", tournament_entry: entry)
      end
    end
  end
end
