require "test_helper"

module Decks
  class VersionSnapshotTest < ActiveSupport::TestCase
    setup do
      @deck = users(:one).decks.create!(name: "Snap", format: "other", other_format_name: "Theme Deck")
      @deck.deck_cards.create!(card: cards(:honedge), quantity: 3)
      @deck.deck_cards.create!(card: cards(:trainer_card), quantity: 4)
    end

    test "copies the live list and the three format columns" do
      version = VersionSnapshot.call(@deck)

      assert version.persisted?
      assert_equal "other", version.format
      assert_equal "Theme Deck", version.other_format_name
      assert_nil version.standard_pool_id
      assert_equal @deck.deck_cards.pluck(:card_id, :quantity).sort,
        version.deck_version_cards.pluck(:card_id, :quantity).sort
    end

    test "dates the version now unless told otherwise" do
      freeze_time do
        assert_equal Time.current, VersionSnapshot.call(@deck).effective_at
      end

      assert_in_delta 3.days.ago, VersionSnapshot.call(@deck, effective_at: 3.days.ago).effective_at, 1.second
    end

    # latest_version reads a loaded association without querying, so a snapshot that left it loaded
    # would go on answering the version before it.
    test "a snapshot taken after the deck's versions were loaded is its latest" do
      first = VersionSnapshot.call(@deck, effective_at: 2.days.ago)
      @deck.deck_versions.load
      assert_equal first, @deck.latest_version

      second = VersionSnapshot.call(@deck)

      assert_equal second, @deck.latest_version
    end

    test "raises rather than answering an unsaved version" do
      assert_raises(ActiveRecord::RecordInvalid) do
        VersionSnapshot.call(@deck, effective_at: 1.day.from_now)
      end
      assert_empty @deck.deck_versions.reload
    end
  end
end
