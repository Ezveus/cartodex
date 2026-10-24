require "test_helper"

module Decks
  class DeckCardQuantitySetterTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      @card = cards(:honedge)
      @user.collections.find_or_create_by!(card: @card).update!(quantity: 3)
      @deck = @user.decks.create!(name: "A", physical: true, standard_pool: standard_pools(:twm_por))
      @deck.deck_cards.create!(card: @card, quantity: 4, owned_copies: 3)
    end

    test "reducing quantity below owned_copies recaps the reals" do
      dc = Decks::DeckCardQuantitySetter.call(deck: @deck, card: @card, quantity: 2)
      assert_equal 2, dc.quantity
      assert_equal 2, dc.owned_copies
    end

    test "setting quantity to 0 removes the deck_card" do
      result = Decks::DeckCardQuantitySetter.call(deck: @deck, card: @card, quantity: 0)
      assert_nil result
      assert_nil @deck.deck_cards.find_by(card: @card)
    end

    test "rejects non-integer quantity without destroying the deck_card" do
      assert_raises(ArgumentError) do
        Decks::DeckCardQuantitySetter.call(deck: @deck, card: @card, quantity: "abc")
      end
      assert_equal 4, @deck.deck_cards.find_by(card: @card).quantity # unchanged, not destroyed
    end

    # Replaces "does not auto-bump reals when increasing quantity": an increase now applies the
    # backing rule Decks::CardAdder applies, so the real + is not left refusing after a quantity +.
    test "an increase claims the free copies, counting this deck's own reals as its own" do
      @deck.deck_cards.find_by!(card: @card).update!(quantity: 1, owned_copies: 1)

      dc = Decks::DeckCardQuantitySetter.call(deck: @deck, card: @card, quantity: 3)

      assert_equal 3, dc.quantity
      assert_equal 3, dc.owned_copies
    end

    test "an increase claims only what another physical deck leaves free" do
      @deck.deck_cards.find_by!(card: @card).update!(quantity: 1, owned_copies: 1)
      other = @user.decks.create!(name: "B", physical: true, standard_pool: standard_pools(:twm_por))
      other.deck_cards.create!(card: @card, quantity: 1, owned_copies: 1)

      dc = Decks::DeckCardQuantitySetter.call(deck: @deck, card: @card, quantity: 3)

      assert_equal 3, dc.quantity
      assert_equal 2, dc.owned_copies
    end

    test "a decrease never claims a free copy" do
      @deck.deck_cards.find_by!(card: @card).update!(quantity: 4, owned_copies: 1)

      dc = Decks::DeckCardQuantitySetter.call(deck: @deck, card: @card, quantity: 3)

      assert_equal 3, dc.quantity
      assert_equal 1, dc.owned_copies, "the copy dropped was a proxy, and nothing was claimed"
    end

    test "a non-physical deck never claims" do
      deck = @user.decks.create!(name: "Live", physical: false, standard_pool: standard_pools(:twm_por))
      deck.deck_cards.create!(card: @card, quantity: 1, owned_copies: 0)

      dc = Decks::DeckCardQuantitySetter.call(deck: deck, card: @card, quantity: 3)

      assert_equal 3, dc.quantity
      assert_equal 0, dc.owned_copies
    end

    test "a new row counts as an increase from 0" do
      @user.collections.find_by!(card: @card).update!(quantity: 2)
      @deck.deck_cards.find_by!(card: @card).destroy!
      deck = @user.decks.create!(name: "C", physical: true, standard_pool: standard_pools(:twm_por))

      dc = Decks::DeckCardQuantitySetter.call(deck: deck, card: @card, quantity: 3)

      assert_equal 3, dc.quantity
      assert_equal 2, dc.owned_copies
    end

    test "a new row on a non-physical deck claims nothing" do
      deck = @user.decks.create!(name: "Live", physical: false, standard_pool: standard_pools(:twm_por))

      dc = Decks::DeckCardQuantitySetter.call(deck: deck, card: @card, quantity: 3)

      assert_equal 3, dc.quantity
      assert_equal 0, dc.owned_copies
    end

    # The availability read and the write must sit under one write lock, or two concurrent
    # increases each see the same free copy and both claim it. Depth rather than "BEGIN IMMEDIATE
    # was issued", for the reason test/mcp/bulk_add_tools_test.rb gives: under fixtures the
    # service's own transaction is a savepoint.
    test "the availability is read inside the write transaction" do
      baseline = ActiveRecord::Base.connection.open_transactions
      depths = []
      original = Allocations::Availability.method(:for_cards)
      Allocations::Availability.define_singleton_method(:for_cards) do |**kwargs|
        depths << ActiveRecord::Base.connection.open_transactions
        original.call(**kwargs)
      end

      begin
        Decks::DeckCardQuantitySetter.call(deck: @deck, card: @card, quantity: 6)
      ensure
        # Restored rather than removed: `for_cards` is Availability's own singleton method, so
        # removing the stub would remove it for every later test in this process.
        Allocations::Availability.define_singleton_method(:for_cards, original)
      end

      assert_not_empty depths, "an increase on a physical deck read no availability"
      assert depths.all? { |depth| depth > baseline }, "availability was read outside the write transaction"
    end
  end
end
