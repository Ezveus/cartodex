require "test_helper"

# CardsController#index went public (issue behind PubliclyReachable) and picked up a per-IP
# limiter for exactly that reason — nothing before this exercised it. Mirrors the
# with_real_rate_limit_store pattern from test/integration/mcp_server_test.rb: the test
# environment's cache store is :null_store, which makes `rate_limit` a no-op, so a real store
# has to stand in for the duration of the test.
class CardsRateLimitTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "throttles an anonymous client past the index limit, but never a signed-in one" do
    with_real_rate_limit_store do
      limit = CardsController::INDEX_RATE_LIMIT_TO

      limit.times do
        get cards_path
        assert_response :success
      end

      get cards_path
      assert_response :too_many_requests

      # The `unless: -> { user_signed_in? }` guard: a signed-in client is exempt, so it must
      # sail past the same limit that just stopped the anonymous client above.
      sign_in users(:one)

      (limit + 1).times do
        get cards_path
        assert_response :success
      end
    end
  end

  private

  def with_real_rate_limit_store
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    yield
  ensure
    Rails.cache = original_cache
  end
end
