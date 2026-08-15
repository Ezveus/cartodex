require "test_helper"

module Allocations
  # The one rule saying how many of a row's copies a deck may back with owned cards. Written once
  # because three callers apply it — an add, a printing swap, and the picker's projection of that
  # swap — and a projection that disagreed with the write would warn about the wrong thing.
  class BackingTest < ActiveSupport::TestCase
    test "claims as many real copies as the collection leaves free" do
      assert_equal 2, Allocations::Backing.greedy(quantity: 4, current_owned: 0, available: 2)
    end

    test "never backs more copies than the row holds" do
      assert_equal 3, Allocations::Backing.greedy(quantity: 3, current_owned: 0, available: 9)
    end

    test "never demotes copies the deck already backs" do
      # Availability excludes this deck, so its own commitment does not show up as free — reading
      # it as a ceiling would demote a real copy on every unrelated edit.
      assert_equal 2, Allocations::Backing.greedy(quantity: 3, current_owned: 2, available: 0)
    end

    test "caps a preserved backing at the row's total" do
      # The only way current_owned can exceed the total: a collection decrease left the deck
      # over-allocated, and the row then shrank.
      assert_equal 1, Allocations::Backing.greedy(quantity: 1, current_owned: 2, available: 0)
    end
  end
end
