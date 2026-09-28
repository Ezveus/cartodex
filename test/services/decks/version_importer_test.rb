require "test_helper"

module Decks
  class VersionImporterTest < ActiveSupport::TestCase
    setup do
      @deck = users(:one).decks.create!(name: "Past", standard_pool: standard_pools(:twm_por))
    end

    test "creates a version from a pasted PTCG list, section headers and blank lines included" do
      decklist = <<~LIST
        Pokémon: 3

        2 Honedge POR 56
        1 Doublade POR 57

        Trainer: 4
        4 Boss's Orders PAL 172

        Total Cards: 7
      LIST

      result = import(decklist)

      assert_empty result.errors
      version = result.version
      assert version.persisted?
      assert_equal 5.days.ago.to_date, version.effective_at.to_date
      assert_equal standard_pools(:twm_por), version.standard_pool
      assert_equal [ [ cards(:honedge).id, 2 ], [ cards(:doublade).id, 1 ], [ cards(:trainer_card).id, 4 ] ].sort,
        version.deck_version_cards.pluck(:card_id, :quantity).sort
    end

    test "sums a printing written on two lines" do
      result = import("2 Honedge POR 56\n1 Honedge POR 56")

      assert_empty result.errors
      assert_equal [ [ cards(:honedge).id, 3 ] ], result.version.deck_version_cards.pluck(:card_id, :quantity)
    end

    # Decks::Fetcher drops a line it cannot read and imports a shorter deck; a reconstruction of
    # a list that was played has no business doing the same.
    test "refuses a line it cannot read, by name, and writes nothing" do
      result = nil
      assert_no_difference -> { DeckVersion.count } do
        result = import("2 Honedge POR 56\n4 Honedge POR")
      end

      assert_nil result.version
      assert_equal 1, result.errors.size
      assert_match "4 Honedge POR", result.errors.first
    end

    test "refuses a printing the catalogue does not hold, by name, and writes nothing" do
      result = nil
      assert_no_difference [ -> { DeckVersion.count }, -> { DeckVersionCard.count } ] do
        result = import("2 Honedge POR 56\n1 Missing POR 999")
      end

      assert_nil result.version
      assert_equal 1, result.errors.size
      assert_match "POR 999", result.errors.first
    end

    test "refuses a list with no card line" do
      result = import("Pokémon: 0\n\n")

      assert_nil result.version
      assert_not_empty result.errors
    end

    test "reports the version's own validation errors" do
      result = import("2 Honedge POR 56", effective_at: 1.day.from_now)

      assert_nil result.version
      assert_includes result.errors, "Effective at can't be in the future"
      assert_empty @deck.deck_versions.reload
    end

    private

    def import(decklist, effective_at: 5.days.ago)
      VersionImporter.call(deck: @deck, decklist: decklist, effective_at: effective_at,
        format: "standard", standard_pool: standard_pools(:twm_por), other_format_name: nil)
    end
  end
end
