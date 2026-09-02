ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # The extra printings a flat-cost test adds to make its "large" input, so the
    # three tests that measure one live in one place rather than repeating the
    # fixture list.
    FLAT_COST_EXTRA_CARDS = %i[doublade trainer_card froakie_cri basic_psychic_energy].freeze

    # Number of real queries a block issues, ignoring schema lookups and anything
    # the query cache served. Complements assert_queries_count, which asserts an
    # exact number: this returns the count, so a test can assert that two
    # differently-sized inputs cost the *same* without pinning what that is.
    # Clears the query cache first: two measurements of the same code in one
    # process would otherwise see the second one served entirely from cache and
    # report zero, making a growing count look like a shrinking one.
    #
    # Counting is delegated to the SQLCounter rails/test_help already loads, so
    # "a real query" keeps whatever definition Rails gives it.
    def count_queries(&block)
      ActiveRecord::Base.connection.clear_query_cache
      counter = ActiveRecord::Assertions::QueryAssertions::SQLCounter.new
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
      counter.log.size
    end

    # Grows the user's collection by FLAT_COST_EXTRA_CARDS: the "large" input of a
    # flat-cost test. Returns the cards added, so a caller can put them in a deck
    # too.
    def grow_collection(user, quantity: 2)
      FLAT_COST_EXTRA_CARDS.map do |fixture_name|
        cards(fixture_name).tap do |card|
          user.collections.find_or_create_by!(card: card) { |c| c.quantity = 0 }.update!(quantity: quantity)
        end
      end
    end

    # Leaves the user with one over-allocated card, in a deck of its own.
    #
    # Flat-cost tests need this before their first measurement. They compare
    # whole-request query counts, and Allocations::OverAllocations — which every
    # collection and deck page runs — returns early when nothing is
    # over-allocated. Without a standing over-allocation, a measurement that
    # crossed from that early return into the full path would report a growth
    # that is a branch change, not the N+1 the test is looking for.
    def force_over_allocation(user, card: cards(:teal_mask_ogerpon_ex))
      user.collections.find_or_create_by!(card: card) { |c| c.quantity = 0 }
      deck = user.decks.create!(name: "Over-allocated", physical: true, standard_pool: StandardPool.current)
      deck.deck_cards.create!(card: card, quantity: 1, owned_copies: 1)
      deck
    end

    # Commits more real copies of the card across a fresh physical deck than the
    # user owns — the state a collection decrease leaves behind. Uses @user, set
    # by the including test's setup.
    def over_allocate(card, owned:, committed:)
      @user.collections.find_or_create_by!(card: card) { |c| c.quantity = 0 }.update!(quantity: owned)
      @user.decks.create!(name: "Deck #{card.id}", physical: true, standard_pool: standard_pools(:twm_por)).tap do |deck|
        deck.deck_cards.create!(card: card, quantity: committed, owned_copies: committed)
      end
    end
  end
end
