require "test_helper"

module Decks
  class CollectionCopyAdderTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      @card = cards(:honedge) # collection fixture `one`: 1 owned
      @deck = @user.decks.create!(name: "Physical", physical: true, standard_pool: standard_pools(:twm_por))
    end

    def owned = @user.collections.where(card: @card).sum(:quantity)

    test "adds one copy to the collection and backs one proxy with it" do
      @deck.deck_cards.create!(card: @card, quantity: 3, owned_copies: 1)

      deck_card = nil
      assert_difference -> { owned }, 1 do
        deck_card = CollectionCopyAdder.call(deck: @deck, card: @card)
      end

      assert_equal 3, deck_card.quantity
      assert_equal 2, deck_card.owned_copies
      assert_equal 2, @deck.deck_cards.find_by!(card: @card).owned_copies
    end

    test "the collection copy lands in the unknown language and finish" do
      @deck.deck_cards.create!(card: @card, quantity: 2, owned_copies: 1)

      CollectionCopyAdder.call(deck: @deck, card: @card)

      assert_equal 2, @user.collections.find_by!(card: @card, language: "unknown", finish: "unknown").quantity
    end

    test "refuses a non-physical deck, which consumes no collection" do
      deck = @user.decks.create!(name: "Live", physical: false, standard_pool: standard_pools(:twm_por))
      deck.deck_cards.create!(card: @card, quantity: 2)

      assert_no_difference -> { owned } do
        assert_raises(OwnedCopiesSetter::NotPhysicalError) { CollectionCopyAdder.call(deck: deck, card: @card) }
      end
    end

    test "refuses a card the deck does not hold" do
      assert_no_difference -> { owned } do
        assert_raises(ActiveRecord::RecordNotFound) { CollectionCopyAdder.call(deck: @deck, card: @card) }
      end
    end

    test "refuses when every copy is already real" do
      @deck.deck_cards.create!(card: @card, quantity: 1, owned_copies: 1)

      assert_no_difference -> { owned } do
        error = assert_raises(ArgumentError) { CollectionCopyAdder.call(deck: @deck, card: @card) }
        assert_equal "no proxy left to back", error.message
      end
    end

    # The owner's rule: the click adds one copy and then backs greedily, so with a free copy already
    # in the collection it claims that one too — two proxies backed by one click.
    test "with a free copy already in the collection, adds one and backs every proxy it can" do
      @user.collections.find_by!(card: @card).update!(quantity: 2)
      @deck.deck_cards.create!(card: @card, quantity: 4, owned_copies: 1)

      deck_card = nil
      assert_difference -> { owned }, 1 do
        deck_card = CollectionCopyAdder.call(deck: @deck, card: @card)
      end

      assert_equal 3, deck_card.owned_copies, "the free copy and the new one"
      assert_equal 3, @deck.deck_cards.find_by!(card: @card).owned_copies
    end

    # Two physical decks back 2 reals out of 1 owned. One more copy only brings the collection back
    # to what is already committed, so it cannot back a proxy here — and the collection write must
    # roll back with the refusal rather than leave a copy nobody asked for.
    test "refuses an over-allocated printing and rolls the collection write back" do
      @deck.deck_cards.create!(card: @card, quantity: 2, owned_copies: 1)
      other = @user.decks.create!(name: "Other", physical: true, standard_pool: standard_pools(:twm_por))
      other.deck_cards.create!(card: @card, quantity: 1, owned_copies: 1)

      assert_no_difference -> { owned } do
        assert_raises(ArgumentError) { CollectionCopyAdder.call(deck: @deck, card: @card) }
      end
      assert_equal 1, @deck.deck_cards.find_by!(card: @card).owned_copies
    end

    test "the collection write and the backing share one transaction" do
      @deck.deck_cards.create!(card: @card, quantity: 3, owned_copies: 1)
      baseline = ActiveRecord::Base.connection.open_transactions
      depths = []
      original = Collections::CardAdder.method(:call)
      Collections::CardAdder.define_singleton_method(:call) do |**kwargs|
        depths << ActiveRecord::Base.connection.open_transactions
        original.call(**kwargs)
      end

      begin
        CollectionCopyAdder.call(deck: @deck, card: @card)
      ensure
        Collections::CardAdder.singleton_class.send(:remove_method, :call)
      end

      assert_equal 1, depths.size
      assert depths.first > baseline, "the collection was written outside the adder's transaction"
    end
  end
end
