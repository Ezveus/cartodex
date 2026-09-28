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
