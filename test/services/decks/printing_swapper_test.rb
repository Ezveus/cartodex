require "test_helper"

module Decks
  class PrintingSwapperTest < ActiveSupport::TestCase
    setup do
      # budew_pre and budew_asc share fingerprint "budew_shared" in fixtures.
      @user = users(:one)
      @asc = cards(:budew_asc)
      @pre = cards(:budew_pre)
      @deck = @user.decks.create!(name: "Physical", physical: true)
    end

    test "moves the slot to the target printing, keeping its quantity" do
      @deck.deck_cards.create!(card: @asc, quantity: 3)

      deck_card = Decks::PrintingSwapper.call(deck: @deck, card: @asc, target_card: @pre)

      assert_equal @pre.id, deck_card.card_id
      assert_equal 3, deck_card.quantity
      assert_equal [ @pre.id ], @deck.deck_cards.reload.map(&:card_id)
    end

    test "backs the new printing with whatever the collection leaves available" do
      @user.collections.find_by!(card: @pre).update!(quantity: 4)
      @deck.deck_cards.create!(card: @asc, quantity: 3)

      deck_card = Decks::PrintingSwapper.call(deck: @deck, card: @asc, target_card: @pre)

      assert_equal 3, deck_card.owned_copies
    end

    test "converts real copies to proxies when the target printing is not owned" do
      @user.collections.find_by!(card: @asc).update!(quantity: 2)
      @deck.deck_cards.create!(card: @asc, quantity: 3, owned_copies: 2)

      deck_card = Decks::PrintingSwapper.call(deck: @deck, card: @asc, target_card: @pre)

      assert_equal 0, deck_card.owned_copies
      assert_equal 3, deck_card.proxies
    end

    test "never backs more copies than the target printing leaves available to this deck" do
      @user.collections.find_by!(card: @pre).update!(quantity: 3)
      other = @user.decks.create!(name: "Other", physical: true)
      other.deck_cards.create!(card: @pre, quantity: 2, owned_copies: 2)
      @deck.deck_cards.create!(card: @asc, quantity: 4)

      deck_card = Decks::PrintingSwapper.call(deck: @deck, card: @asc, target_card: @pre)

      assert_equal 1, deck_card.owned_copies
    end

    test "merges into an existing row for the target printing" do
      @deck.deck_cards.create!(card: @asc, quantity: 2)
      @deck.deck_cards.create!(card: @pre, quantity: 1)

      deck_card = Decks::PrintingSwapper.call(deck: @deck, card: @asc, target_card: @pre)

      assert_equal 3, deck_card.quantity
      assert_equal [ @pre.id ], @deck.deck_cards.reload.map(&:card_id)
      assert_equal 3, @deck.deck_cards.sum(&:quantity), "a swap never changes the deck's size"
    end

    test "keeps the copies an existing target row already backs" do
      @user.collections.find_by!(card: @pre).update!(quantity: 1)
      @deck.deck_cards.create!(card: @asc, quantity: 2)
      @deck.deck_cards.create!(card: @pre, quantity: 1, owned_copies: 1)

      deck_card = Decks::PrintingSwapper.call(deck: @deck, card: @asc, target_card: @pre)

      assert_equal 3, deck_card.quantity
      assert_equal 1, deck_card.owned_copies
    end

    test "leaves a non-physical deck's row unbacked" do
      live = @user.decks.create!(name: "Live", physical: false)
      live.deck_cards.create!(card: @asc, quantity: 2)
      @user.collections.find_by!(card: @pre).update!(quantity: 4)

      deck_card = Decks::PrintingSwapper.call(deck: live, card: @asc, target_card: @pre)

      assert_equal 0, deck_card.owned_copies
    end

    test "rejects swapping a printing for itself" do
      @deck.deck_cards.create!(card: @asc, quantity: 1)

      assert_raises(ArgumentError) do
        Decks::PrintingSwapper.call(deck: @deck, card: @asc, target_card: @asc)
      end
    end

    test "rejects a card that is not another printing of the same card" do
      @deck.deck_cards.create!(card: @asc, quantity: 1)

      assert_raises(ArgumentError) do
        Decks::PrintingSwapper.call(deck: @deck, card: @asc, target_card: cards(:froakie_cri))
      end
    end

    test "rejects a card whose fingerprint is blank" do
      trainer = cards(:trainer_card)
      @deck.deck_cards.create!(card: trainer, quantity: 1)

      assert_raises(ArgumentError) do
        Decks::PrintingSwapper.call(deck: @deck, card: trainer, target_card: cards(:bosss_orders_meg))
      end
    end

    test "raises when the deck does not hold the card" do
      assert_raises(ActiveRecord::RecordNotFound) do
        Decks::PrintingSwapper.call(deck: @deck, card: @asc, target_card: @pre)
      end
    end
  end
end
