require "test_helper"

module Decks
  class CopyMoverTest < ActiveSupport::TestCase
    setup do
      # budew_pre and budew_asc share fingerprint "budew_shared" in fixtures.
      @user = users(:one)
      @pre = cards(:budew_pre)
      @asc = cards(:budew_asc)
      @deck = @user.decks.create!(name: "Physical", physical: true, standard_pool: standard_pools(:twm_por))
    end

    test "refuses to move a printing onto itself" do
      @deck.deck_cards.create!(card: @pre, quantity: 2)

      error = assert_raises(ArgumentError) { CopyMover.call(deck: @deck, from_card: @pre, to_card: @pre) }
      assert_match(/same printing/, error.message)
    end

    test "refuses a card that is not another printing of the source" do
      @deck.deck_cards.create!(card: cards(:honedge), quantity: 2)

      assert_no_difference "::DeckCard.count" do
        assert_raises(ArgumentError) { CopyMover.call(deck: @deck, from_card: cards(:honedge), to_card: @asc) }
      end
      assert_equal 2, @deck.deck_cards.find_by!(card: cards(:honedge)).quantity
    end

    # A blank fingerprint matches every other blank, so two unfingerprinted cards are no evidence
    # of being one card.
    test "refuses two cards whose fingerprints are both blank" do
      asc_prism = cards(:special_prism_energy_asc)
      blk_prism = cards(:special_prism_energy_blk)
      @deck.deck_cards.create!(card: asc_prism, quantity: 1)

      assert_raises(ArgumentError) { CopyMover.call(deck: @deck, from_card: asc_prism, to_card: blk_prism) }
      assert_nil @deck.deck_cards.find_by(card: blk_prism)
    end

    test "refuses a source the deck does not hold" do
      assert_no_difference "::DeckCard.count" do
        error = assert_raises(ArgumentError) { CopyMover.call(deck: @deck, from_card: @pre, to_card: @asc) }
        assert_match(/not in the deck/, error.message)
      end
    end

    test "moves one copy and destroys the source row when it reaches 0" do
      @deck.deck_cards.create!(card: @pre, quantity: 1)

      result = CopyMover.call(deck: @deck, from_card: @pre, to_card: @asc)

      assert_nil result.from_deck_card
      assert_nil @deck.deck_cards.find_by(card: @pre)
      assert_equal 1, result.to_deck_card.quantity
      assert_equal @asc, result.to_deck_card.card
      assert result.to_deck_card.persisted?
    end

    test "drops a proxy first from the source" do
      @deck.deck_cards.create!(card: @pre, quantity: 3, owned_copies: 1)
      @user.collections.find_by!(card: @pre).update!(quantity: 1)

      result = CopyMover.call(deck: @deck, from_card: @pre, to_card: @asc)

      assert_equal 2, result.from_deck_card.quantity
      assert_equal 1, result.from_deck_card.owned_copies
    end

    test "drops a real only when the source has no proxy left" do
      @deck.deck_cards.create!(card: @pre, quantity: 2, owned_copies: 2)
      @user.collections.find_by!(card: @pre).update!(quantity: 2)

      result = CopyMover.call(deck: @deck, from_card: @pre, to_card: @asc)

      assert_equal 1, result.from_deck_card.quantity
      assert_equal 1, result.from_deck_card.owned_copies
    end

    test "backs the landed copy greedily with what the collection leaves free" do
      @deck.deck_cards.create!(card: @pre, quantity: 2)
      @deck.deck_cards.create!(card: @asc, quantity: 1, owned_copies: 1)
      @user.collections.find_by!(card: @asc).update!(quantity: 3)
      other = @user.decks.create!(name: "Other", physical: true, standard_pool: standard_pools(:twm_por))
      other.deck_cards.create!(card: @asc, quantity: 1, owned_copies: 1)

      result = CopyMover.call(deck: @deck, from_card: @pre, to_card: @asc)

      assert_equal 2, result.to_deck_card.quantity
      assert_equal 2, result.to_deck_card.owned_copies
      assert_equal 1, result.from_deck_card.quantity
    end

    test "lands a proxy when no copy of the target is free" do
      @deck.deck_cards.create!(card: @pre, quantity: 2)
      @user.collections.find_by!(card: @asc).update!(quantity: 1)
      other = @user.decks.create!(name: "Other", physical: true, standard_pool: standard_pools(:twm_por))
      other.deck_cards.create!(card: @asc, quantity: 1, owned_copies: 1)

      result = CopyMover.call(deck: @deck, from_card: @pre, to_card: @asc)

      assert_equal 1, result.to_deck_card.quantity
      assert_equal 0, result.to_deck_card.owned_copies
    end

    test "never backs anything on a non-physical deck" do
      deck = @user.decks.create!(name: "Live", physical: false, standard_pool: standard_pools(:twm_por))
      deck.deck_cards.create!(card: @pre, quantity: 2)
      @user.collections.find_by!(card: @asc).update!(quantity: 3)

      result = CopyMover.call(deck: deck, from_card: @pre, to_card: @asc)

      assert_equal 1, result.to_deck_card.quantity
      assert_equal 0, result.to_deck_card.owned_copies
      assert_equal 1, result.from_deck_card.quantity
    end
  end
end
