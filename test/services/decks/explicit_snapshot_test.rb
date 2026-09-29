require "test_helper"

module Decks
  class ExplicitSnapshotTest < ActiveSupport::TestCase
    setup do
      @deck = users(:one).decks.create!(name: "Explicit", standard_pool: standard_pools(:twm_por))
      @deck.deck_cards.create!(card: cards(:honedge), quantity: 2)
    end

    test "records version 1 on a deck with none" do
      result = nil
      assert_difference -> { DeckVersion.count }, 1 do
        result = ExplicitSnapshot.call(@deck)
      end

      assert_equal 1, result.version.number
    end

    test "refuses while the live list matches the latest version, answering it" do
      v1 = VersionSnapshot.call(@deck)

      result = nil
      assert_no_difference -> { DeckVersion.count } do
        result = ExplicitSnapshot.call(@deck.reload)
      end

      assert_nil result.version
      assert_equal v1, result.latest
    end

    test "records the live list as the next version once it has drifted" do
      VersionSnapshot.call(@deck)
      @deck.deck_cards.create!(card: cards(:doublade), quantity: 1)

      result = ExplicitSnapshot.call(@deck.reload)

      assert_equal 2, result.version.number
      assert_equal @deck.deck_cards.pluck(:card_id, :quantity).sort,
        result.version.deck_version_cards.pluck(:card_id, :quantity).sort
    end
  end
end
