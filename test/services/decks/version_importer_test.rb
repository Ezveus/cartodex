require "test_helper"

module Decks
  class VersionImporterTest < ActiveSupport::TestCase
    setup do
      @deck = users(:one).decks.create!(name: "Past", standard_pool: standard_pools(:twm_por))
    end

    test "creates a version from a pasted PTCG list, section headers and blank lines included" do
      record(1.day.ago, doublade: 4)
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
      record(1.day.ago, doublade: 4)
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

    test "refuses a quantity outside 1..60, naming the line, and writes nothing" do
      result = nil
      assert_no_difference -> { DeckVersion.count } do
        result = import("2 Honedge POR 56\n0 Doublade POR 57\n61 Honedge POR 56")
      end

      assert_nil result.version
      assert_equal [ "Line 2: quantity must be between 1 and 60.", "Line 3: quantity must be between 1 and 60." ],
        result.errors
    end

    test "sixty copies on one line is a quantity it accepts" do
      record(1.day.ago, doublade: 4)
      result = import("60 Honedge POR 56")

      assert_empty result.errors
      assert_equal [ 60 ], result.version.deck_version_cards.pluck(:quantity)
    end

    # --- an earlier version must be earlier (P3) ------------------------------------------------

    # With no version, the import would become the latest and the live list would be measured
    # against it: the first result logged afterwards would ask to be filed under a past list.
    test "refuses a deck with no version yet, and writes nothing" do
      result = nil
      assert_no_difference -> { DeckVersion.count } do
        result = import("3 Honedge POR 56")
      end

      assert_nil result.version
      assert_equal [ VersionImporter::NO_VERSION ], result.errors
    end

    test "refuses a date after the latest version's, naming it and its date" do
      record(Time.zone.local(2025, 9, 1, 10), honedge: 2)
      record(Time.zone.local(2025, 9, 23, 10), doublade: 2)

      result = nil
      assert_no_difference -> { DeckVersion.count } do
        result = import("3 Honedge POR 56", effective_at: Time.zone.local(2025, 9, 25, 10))
      end

      assert_nil result.version
      assert_equal [ "Effective from must be before v2 (September 23, 2025)." ], result.errors
    end

    test "refuses the latest version's own instant: before means strictly before" do
      at = Time.zone.local(2025, 9, 23, 10)
      record(at, doublade: 2)

      result = import("3 Honedge POR 56", effective_at: at)

      assert_equal [ "Effective from must be before v1 (September 23, 2025)." ], result.errors
    end

    # The form posts a string; the rule must read the date the version will carry, not the text.
    # 09:00 is an hour before the latest in Paris, and an hour after it read as UTC.
    test "reads a posted date string the way the version will" do
      record(Time.zone.local(2025, 9, 23, 10), doublade: 2)

      assert_equal [ "Effective from must be before v1 (September 23, 2025)." ],
        import("3 Honedge POR 56", effective_at: "2025-09-23T11:00").errors
      assert_empty import("3 Honedge POR 56", effective_at: "2025-09-23T09:00").errors
    end

    # --- identical to a neighbour (P4) -----------------------------------------------------------

    test "refuses a list identical to the version just before the chosen date" do
      record(Time.zone.local(2025, 9, 1, 10), honedge: 2)
      record(Time.zone.local(2025, 9, 23, 10), doublade: 2)

      result = nil
      assert_no_difference -> { DeckVersion.count } do
        result = import("2 Honedge POR 56", effective_at: Time.zone.local(2025, 9, 10, 10))
      end

      assert_equal [ "This list is identical to v1." ], result.errors
    end

    test "refuses a list identical to the version just after the chosen date" do
      record(Time.zone.local(2025, 9, 1, 10), honedge: 2)
      record(Time.zone.local(2025, 9, 23, 10), doublade: 2)

      result = import("2 Doublade POR 57", effective_at: Time.zone.local(2025, 9, 10, 10))

      assert_equal [ "This list is identical to v2." ], result.errors
    end

    # The new version ranks after every version sharing its instant (its id is higher), so dated at
    # v1's exact instant its neighbour after is v2 — never v1 twice.
    test "at a neighbour's exact instant, the version after is still compared" do
      at = Time.zone.local(2025, 9, 1, 10)
      record(at, honedge: 2)
      record(Time.zone.local(2025, 9, 23, 10), doublade: 2)

      assert_equal [ "This list is identical to v2." ], import("2 Doublade POR 57", effective_at: at).errors
    end

    # Compared exactly as drift compares: by fingerprint and summed quantity.
    test "a printing split of the neighbour's list is identical to it" do
      record(Time.zone.local(2025, 9, 23, 10), budew_pre: 4)

      result = import("2 Budew PRE 4\n2 Budew ASC 16", effective_at: Time.zone.local(2025, 9, 10, 10))

      assert_equal [ "This list is identical to v1." ], result.errors
    end

    test "the same cards under another pool are not identical" do
      record(Time.zone.local(2025, 9, 23, 10), honedge: 2)

      result = VersionImporter.call(deck: @deck, decklist: "2 Honedge POR 56",
        effective_at: Time.zone.local(2025, 9, 10, 10), format: "standard",
        standard_pool: standard_pools(:twm_asc), other_format_name: nil)

      assert_empty result.errors
    end

    # Only the neighbours: a list played again after an interlude is a legitimate version.
    test "a list identical to a version that is not a neighbour is accepted" do
      record(Time.zone.local(2025, 9, 1, 10), honedge: 2)
      record(Time.zone.local(2025, 9, 10, 10), doublade: 2)
      record(Time.zone.local(2025, 9, 23, 10), doublade: 3)

      result = import("2 Honedge POR 56", effective_at: Time.zone.local(2025, 9, 15, 10))

      assert_empty result.errors
      assert_equal 3, result.version.number
    end

    private

    def import(decklist, effective_at: 5.days.ago)
      VersionImporter.call(deck: @deck, decklist: decklist, effective_at: effective_at,
        format: "standard", standard_pool: standard_pools(:twm_por), other_format_name: nil)
    end

    def record(effective_at, pool: standard_pools(:twm_por), **quantities)
      version = @deck.deck_versions.create!(effective_at: effective_at, format: "standard", standard_pool: pool)
      quantities.each { |name, quantity| version.deck_version_cards.create!(card: cards(name), quantity: quantity) }
      @deck.deck_versions.reset
      version
    end
  end
end
