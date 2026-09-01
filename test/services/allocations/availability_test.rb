require "test_helper"

module Allocations
  class AvailabilityTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      @card = cards(:honedge)
      @user.collections.find_or_create_by!(card: @card).update!(quantity: 3)
      @deck_a = @user.decks.create!(name: "A", physical: true, standard_pool: standard_pools(:twm_por))
      @deck_b = @user.decks.create!(name: "B", physical: true, standard_pool: standard_pools(:twm_por))
    end

    test "available equals owned when nothing is committed" do
      result = Allocations::Availability.call(user: @user, card: @card)
      assert_equal 3, result.owned
      assert_equal 0, result.committed
      assert_equal 3, result.available
    end

    test "committed sums owned_copies across physical decks; available is the remainder" do
      @deck_a.deck_cards.create!(card: @card, quantity: 2, owned_copies: 2)
      @deck_b.deck_cards.create!(card: @card, quantity: 1, owned_copies: 1)

      result = Allocations::Availability.call(user: @user, card: @card)
      assert_equal 3, result.committed
      assert_equal 0, result.available
    end

    test "excluding_deck frees that deck's own committed copies" do
      @deck_a.deck_cards.create!(card: @card, quantity: 2, owned_copies: 2)

      result = Allocations::Availability.call(user: @user, card: @card, excluding_deck: @deck_a)
      assert_equal 2, result.committed         # total committed still 2
      assert_equal 3, result.available         # but deck A's 2 are reclaimable → 3 free for A
    end

    test "non-physical decks do not count toward committed" do
      live = @user.decks.create!(name: "Live", physical: false, standard_pool: standard_pools(:twm_por))
      live.deck_cards.create!(card: @card, quantity: 4) # owned_copies forced 0

      result = Allocations::Availability.call(user: @user, card: @card)
      assert_equal 0, result.committed
      assert_equal 3, result.available
    end

    test "available floors at zero when over-allocated" do
      @deck_a.deck_cards.create!(card: @card, quantity: 3, owned_copies: 3)
      @user.collections.find_by(card: @card).update!(quantity: 2) # sold one

      result = Allocations::Availability.call(user: @user, card: @card)
      assert_equal 2, result.owned
      assert_equal 3, result.committed
      assert_equal 0, result.available
    end

    # Pins the per-card cost so a future change cannot quietly add a round trip.
    # This documents the status quo rather than driving a fix: the call already
    # costs two real queries, because `owned` is asked twice and `committed` /
    # `committed_excluding` generate identical SQL when no deck is excluded, and
    # Rails' query cache absorbs both duplicates. Memoisation removes the two
    # redundant cache lookups but not a round trip — the batching below is what
    # actually changes the cost of a page.
    test "a single call costs two real queries" do
      @deck_a.deck_cards.create!(card: @card, quantity: 2, owned_copies: 2)

      assert_queries_count(2) do
        Allocations::Availability.call(user: @user, card: @card)
      end
    end

    test "excluding a deck costs one extra real query" do
      @deck_a.deck_cards.create!(card: @card, quantity: 2, owned_copies: 2)

      assert_queries_count(3) do
        Allocations::Availability.call(user: @user, card: @card, excluding_deck: @deck_a)
      end
    end

    test "for_cards returns the same numbers as calling per card" do
      other = cards(:doublade)
      @user.collections.create!(card: other, quantity: 1)
      @deck_a.deck_cards.create!(card: @card, quantity: 2, owned_copies: 2)
      @deck_b.deck_cards.create!(card: other, quantity: 1, owned_copies: 1)

      batched = Allocations::Availability.for_cards(user: @user, cards: [ @card, other ])

      [ @card, other ].each do |card|
        single = Allocations::Availability.call(user: @user, card: card)
        assert_equal [ single.owned, single.committed, single.available ],
          [ batched[card.id].owned, batched[card.id].committed, batched[card.id].available ],
          "batched result diverges from the per-card result for #{card.name}"
      end
    end

    test "for_cards honours excluding_deck the same way a single call does" do
      @deck_a.deck_cards.create!(card: @card, quantity: 2, owned_copies: 2)

      batched = Allocations::Availability.for_cards(user: @user, cards: [ @card ], excluding_deck: @deck_a)
      single = Allocations::Availability.call(user: @user, card: @card, excluding_deck: @deck_a)

      assert_equal [ single.owned, single.committed, single.available ],
        [ batched[@card.id].owned, batched[@card.id].committed, batched[@card.id].available ]
    end

    test "for_cards reports zeroes for a card the user does not own" do
      unowned = cards(:trainer_card)

      batched = Allocations::Availability.for_cards(user: @user, cards: [ unowned ])

      assert_equal 0, batched[unowned.id].owned
      assert_equal 0, batched[unowned.id].committed
      assert_equal 0, batched[unowned.id].available
    end

    # The point of the batch API: the query count must not grow with the number
    # of cards. Two cards and six cards must cost the same.
    test "for_cards issues a constant number of queries regardless of card count" do
      cards_two = [ @card, cards(:doublade) ]
      cards_six = cards_two + [ cards(:trainer_card), cards(:budew_pre), cards(:budew_asc), cards(:froakie_cri) ]

      two = count_queries { Allocations::Availability.for_cards(user: @user, cards: cards_two) }
      six = count_queries { Allocations::Availability.for_cards(user: @user, cards: cards_six) }

      assert_equal two, six, "query count grew with the number of cards: #{two} -> #{six}"
      assert_operator two, :<=, 3, "expected at most three grouped queries, got #{two}"
    end

    test "for_cards issues no query at all for an empty card list" do
      assert_queries_count(0) do
        assert_empty Allocations::Availability.for_cards(user: @user, cards: [])
      end
    end
  end
end
