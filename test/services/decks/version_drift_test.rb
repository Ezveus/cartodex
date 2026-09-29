require "test_helper"

module Decks
  class VersionDriftTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      @deck = @user.decks.create!(name: "Drifting", physical: true, standard_pool: standard_pools(:twm_por))
    end

    test "a deck with no version has no drift and no latest" do
      @deck.deck_cards.create!(card: cards(:honedge), quantity: 2)

      drift = VersionDrift.call(@deck)

      assert_not drift.drift?
      assert_nil drift.latest
    end

    test "an unchanged deck has no drift" do
      @deck.deck_cards.create!(card: cards(:honedge), quantity: 2)
      version = VersionSnapshot.call(@deck)

      drift = VersionDrift.call(@deck.reload)

      assert_not drift.drift?
      assert_equal version, drift.latest
    end

    test "an added card is drift" do
      @deck.deck_cards.create!(card: cards(:honedge), quantity: 2)
      VersionSnapshot.call(@deck)
      @deck.deck_cards.create!(card: cards(:doublade), quantity: 1)

      assert VersionDrift.call(@deck.reload).drift?
    end

    test "a printing swap within one fingerprint is not drift" do
      @deck.deck_cards.create!(card: cards(:budew_pre), quantity: 4)
      VersionSnapshot.call(@deck)
      @deck.deck_cards.sole.update!(card: cards(:budew_asc))

      assert_not VersionDrift.call(@deck.reload).drift?
    end

    test "four copies split two and two across printings is not drift" do
      @deck.deck_cards.create!(card: cards(:budew_pre), quantity: 4)
      VersionSnapshot.call(@deck)
      @deck.deck_cards.sole.update!(quantity: 2)
      @deck.deck_cards.create!(card: cards(:budew_asc), quantity: 2)

      assert_not VersionDrift.call(@deck.reload).drift?
    end

    # With no fingerprint to say two printings are one card, card_id is all there is.
    test "swapping between two unfingerprinted printings is drift" do
      @deck.deck_cards.create!(card: cards(:special_prism_energy_asc), quantity: 2)
      VersionSnapshot.call(@deck)
      @deck.deck_cards.sole.update!(card: cards(:special_prism_energy_blk))

      assert VersionDrift.call(@deck.reload).drift?
    end

    test "a pool change is drift" do
      VersionSnapshot.call(@deck)
      @deck.update!(standard_pool: standard_pools(:twm_asc))

      assert VersionDrift.call(@deck.reload).drift?
    end

    test "a change of the custom format's name is drift" do
      @deck.update!(format: "other", other_format_name: "Gym Leader Challenge")
      VersionSnapshot.call(@deck)
      @deck.update!(other_format_name: "Theme Deck")

      assert VersionDrift.call(@deck.reload).drift?
    end

    # Allocation is present-state inventory, not a property of the list that was played.
    test "a proxy turned real is not drift" do
      @user.collections.find_or_create_by!(card: cards(:honedge)) { |c| c.quantity = 0 }.update!(quantity: 4)
      @deck.deck_cards.create!(card: cards(:honedge), quantity: 2, owned_copies: 0)
      VersionSnapshot.call(@deck)
      @deck.deck_cards.sole.update!(owned_copies: 2)

      assert_not VersionDrift.call(@deck.reload).drift?
    end

    # An empty fingerprint identifies no more than a missing one: keyed on it, every such card
    # would fold into one "" row and a swap between two of them would compare equal.
    test "swapping between two cards whose fingerprint is empty is drift" do
      cards(:honedge).update_column(:fingerprint, "")
      cards(:doublade).update_column(:fingerprint, "")
      @deck.deck_cards.create!(card: cards(:honedge), quantity: 2)
      VersionSnapshot.call(@deck)
      @deck.deck_cards.sole.update!(card: cards(:doublade))

      assert VersionDrift.call(@deck.reload).drift?
    end

    # --- what changed, and the sentence that says so ------------------------------------------

    test "an undrifted deck names no change and has no message" do
      VersionSnapshot.call(@deck)

      drift = VersionDrift.call(@deck.reload)

      assert_equal [], drift.changes
      assert_nil drift.message(1)
    end

    test "a card change names the list alone" do
      VersionSnapshot.call(@deck)
      @deck.deck_cards.create!(card: cards(:doublade), quantity: 1)

      drift = VersionDrift.call(@deck.reload)

      assert_equal [ :cards ], drift.changes
      assert_nil drift.from_label
      assert_nil drift.to_label
      assert_equal "The list has changed since version 1.", drift.message(1)
    end

    # Still drift, by the owner's decision: a list played under another pool is another version.
    test "a pool-only change names the pool and both pool names" do
      VersionSnapshot.call(@deck)
      @deck.update!(standard_pool: standard_pools(:twm_asc))

      drift = VersionDrift.call(@deck.reload)

      assert drift.drift?
      assert_equal [ :pool ], drift.changes
      assert_equal "TWM-POR", drift.from_label
      assert_equal "TWM-ASC", drift.to_label
      assert_equal "The Standard pool has changed since version 3 (TWM-POR → TWM-ASC).", drift.message(3)
    end

    test "a format change names both format labels, and the pool is not named twice" do
      VersionSnapshot.call(@deck)
      @deck.update!(format: "expanded")

      drift = VersionDrift.call(@deck.reload)

      assert_equal [ :format ], drift.changes
      assert_equal "The format has changed since version 1 (Standard (TWM-POR) → Expanded).", drift.message(1)
    end

    test "a change of the custom format's name is a format change" do
      @deck.update!(format: "other", other_format_name: "Gym Leader Challenge")
      VersionSnapshot.call(@deck)
      @deck.update!(other_format_name: "Theme Deck")

      drift = VersionDrift.call(@deck.reload)

      assert_equal [ :format ], drift.changes
      assert_equal "Gym Leader Challenge", drift.from_label
      assert_equal "Theme Deck", drift.to_label
    end

    test "the list and the pool together" do
      VersionSnapshot.call(@deck)
      @deck.update!(standard_pool: standard_pools(:twm_asc))
      @deck.deck_cards.create!(card: cards(:doublade), quantity: 1)

      drift = VersionDrift.call(@deck.reload)

      assert_equal [ :cards, :pool ], drift.changes
      assert_equal "The list and the Standard pool have changed since version 2 (TWM-POR → TWM-ASC).", drift.message(2)
    end

    test "the list and the format together" do
      VersionSnapshot.call(@deck)
      @deck.update!(format: "expanded")
      @deck.deck_cards.create!(card: cards(:doublade), quantity: 1)

      drift = VersionDrift.call(@deck.reload)

      assert_equal [ :cards, :format ], drift.changes
      assert_equal "The list and the format have changed since version 1 (Standard (TWM-POR) → Expanded).",
        drift.message(1)
    end

    test "costs at most two queries, however many cards the deck holds" do
      @deck.deck_cards.create!(card: cards(:honedge), quantity: 1)
      VersionSnapshot.call(@deck)
      deck = @deck.reload
      small = ActiveRecord::Base.uncached { count_queries { VersionDrift.call(deck) } }

      FLAT_COST_EXTRA_CARDS.each { |name| @deck.deck_cards.create!(card: cards(name), quantity: 2) }
      %i[budew_pre budew_asc froakie_twm bosss_orders_meg special_prism_energy_asc].each do |name|
        @deck.deck_cards.create!(card: cards(name), quantity: 1)
      end
      VersionSnapshot.call(@deck.reload)
      assert_equal 10, @deck.deck_cards.count
      deck = @deck.reload
      large = ActiveRecord::Base.uncached { count_queries { VersionDrift.call(deck) } }

      assert_operator small, :<=, 2
      assert_equal small, large
    end
  end
end
