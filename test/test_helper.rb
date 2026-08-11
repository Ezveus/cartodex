ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# Not required by rails/test_help. Gives every test assert_queries_count and
# friends, so a batching change can assert the query count actually dropped
# rather than only that the numbers still come out right.
require "active_record/testing/query_assertions"

module ActiveSupport
  class TestCase
    include ActiveRecord::Assertions::QueryAssertions

    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Number of real queries a block issues, ignoring schema lookups and anything
    # the query cache served. Complements assert_queries_count, which asserts an
    # exact number: this returns the count, so a test can assert that two
    # differently-sized inputs cost the *same* without pinning what that is.
    # Clears the query cache first: two measurements of the same code in one
    # process would otherwise see the second one served entirely from cache and
    # report zero, making a growing count look like a shrinking one.
    def count_queries(&block)
      ActiveRecord::Base.connection.clear_query_cache
      count = 0
      counter = ->(_name, _start, _finish, _id, payload) do
        count += 1 unless payload[:name] == "SCHEMA" || payload[:cached]
      end
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
      count
    end
  end
end
