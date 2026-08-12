require "test_helper"

module Allocations
  class OverAllocationsTest < ActiveSupport::TestCase
    test "reports cards committed beyond what is owned, with the decks involved" do
      user = users(:one)
      card = cards(:honedge)
      user.collections.find_or_create_by!(card: card).update!(quantity: 2)
      deck = user.decks.create!(name: "A", physical: true)
      deck.deck_cards.create!(card: card, quantity: 3, owned_copies: 3) # committed 3 > owned 2

      report = Allocations::OverAllocations.call(user: user)

      entry = report.find { |e| e[:card_id] == card.id }
      assert_equal 2, entry[:owned]
      assert_equal 3, entry[:committed]
      assert_equal [ deck.id ], entry[:decks].map { |d| d[:id] }
    end

    test "is empty when nothing is over-allocated" do
      user = users(:two)
      assert_empty Allocations::OverAllocations.call(user: user)
    end

    test "reports every over-allocated card, each with only the decks holding real copies" do
      user = users(:one)
      first = cards(:honedge)
      second = cards(:doublade)
      user.collections.find_or_create_by!(card: first).update!(quantity: 1)
      user.collections.create!(card: second, quantity: 1)
      deck_a = user.decks.create!(name: "A", physical: true)
      deck_b = user.decks.create!(name: "B", physical: true)
      proxy_only = user.decks.create!(name: "Proxies", physical: true)
      deck_a.deck_cards.create!(card: first, quantity: 2, owned_copies: 2)
      deck_b.deck_cards.create!(card: first, quantity: 1, owned_copies: 1)
      deck_a.deck_cards.create!(card: second, quantity: 2, owned_copies: 2)
      proxy_only.deck_cards.create!(card: first, quantity: 3, owned_copies: 0)

      report = Allocations::OverAllocations.call(user: user)

      by_card = report.index_by { |e| e[:card_id] }
      assert_equal [ 3, 1 ], [ by_card[first.id][:committed], by_card[first.id][:owned] ]
      assert_equal [ 2, 1 ], [ by_card[second.id][:committed], by_card[second.id][:owned] ]
      assert_equal [ deck_a.id, deck_b.id ].sort, by_card[first.id][:decks].map { |d| d[:id] }.sort,
        "a deck holding only proxies must not be listed"
      assert_equal [ deck_a.id ], by_card[second.id][:decks].map { |d| d[:id] }
    end

    # The point of the batching: the cost must not grow with the number of
    # over-allocated cards. Previously each card cost an owned query plus a
    # decks query, so this report was an N+1 over the collection.
    test "issues a constant number of queries regardless of how many cards are over-allocated" do
      one_card_user = users(:two)
      card = cards(:froakie_cri)
      one_card_user.collections.create!(card: card, quantity: 0)
      deck = one_card_user.decks.create!(name: "Solo", physical: true)
      deck.deck_cards.create!(card: card, quantity: 1, owned_copies: 1)

      one = count_queries { Allocations::OverAllocations.call(user: one_card_user) }

      many_user = users(:one)
      many_deck = many_user.decks.create!(name: "Many", physical: true)
      [ :honedge, :doublade, :trainer_card, :budew_pre, :budew_asc ].each do |name|
        c = cards(name)
        many_user.collections.find_or_create_by!(card: c) { |col| col.quantity = 0 }.update!(quantity: 0)
        many_deck.deck_cards.create!(card: c, quantity: 1, owned_copies: 1)
      end

      many = count_queries { Allocations::OverAllocations.call(user: many_user) }

      assert_operator many_user.reload.decks.count, :>=, 1
      assert_equal one, many, "query count grew with the number of over-allocated cards: #{one} -> #{many}"
      assert_operator one, :<=, 4, "expected at most four grouped queries, got #{one}"
    end
  end
end
