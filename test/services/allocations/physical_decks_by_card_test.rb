require "test_helper"

module Allocations
  class PhysicalDecksByCardTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      @card = cards(:honedge)
    end

    def physical_deck(name)
      @user.decks.create!(name: name, physical: true, standard_pool: standard_pools(:twm_por))
    end

    test "each deck carries how many real copies of the card it holds" do
      two = physical_deck("Two")
      three = physical_deck("Three")
      two.deck_cards.create!(card: @card, quantity: 4, owned_copies: 2)
      three.deck_cards.create!(card: @card, quantity: 3, owned_copies: 3)

      decks = PhysicalDecksByCard.call(user: @user, card_ids: [ @card.id ], holding: :holding_real_copies)
                                 .fetch(@card.id)

      assert_equal({ "Two" => 2, "Three" => 3 }, decks.to_h { |d| [ d[:name], d[:owned_copies] ] })
    end

    # Created in the reverse of the expected order and with mixed case, so neither insertion order
    # nor a case-sensitive sort can produce the asserted one.
    test "decks come back ordered by name, ignoring case" do
      %w[zebra alpha Mango].each do |name|
        physical_deck(name).deck_cards.create!(card: @card, quantity: 1, owned_copies: 1)
      end

      decks = PhysicalDecksByCard.call(user: @user, card_ids: [ @card.id ], holding: :holding_real_copies)
                                 .fetch(@card.id)

      assert_equal %w[alpha Mango zebra], decks.map { |d| d[:name] }
    end

    # Two names that compare equal once lowered. The deck with the lower id is inserted second, so
    # neither insertion order nor a missing tie-break can produce the asserted order.
    test "decks with the same name are ordered by id" do
      later = physical_deck("Same")
      earlier = @user.decks.create!(id: later.id - 1_000, name: "same", physical: true,
                                    standard_pool: standard_pools(:twm_por))
      [ later, earlier ].each { |deck| deck.deck_cards.create!(card: @card, quantity: 1, owned_copies: 1) }

      decks = PhysicalDecksByCard.call(user: @user, card_ids: [ @card.id ], holding: :holding_real_copies)
                                 .fetch(@card.id)

      assert_equal [ earlier.id, later.id ], decks.map { |d| d[:id] }
    end

    # A deck turned non-physical has its owned_copies released by a callback, which would hide a
    # missing `physical` filter; update_column leaves the copies in place so only the filter can
    # drop the deck.
    test "a non-physical deck is never listed and commits nothing, whatever its rows say" do
      deck = physical_deck("Was physical")
      deck.deck_cards.create!(card: @card, quantity: 2, owned_copies: 2)
      deck.update_column(:physical, false)

      decks = PhysicalDecksByCard.call(user: @user, card_ids: [ @card.id ], holding: :holding_real_copies)

      assert_empty decks
      assert_equal 0, Availability.call(user: @user, card: @card).committed
    end
  end
end
