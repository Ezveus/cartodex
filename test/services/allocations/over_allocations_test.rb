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
  end
end
