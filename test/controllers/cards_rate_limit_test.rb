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

  # The show page's own budget, under its own name. Spending the index's whole budget first is what
  # proves the names are separate: one shared counter would refuse the show request at 61, under
  # its own limit of 120, so a test that only ever hit #show could not see the two merge.
  test "the card page has its own visitor budget, apart from the index's" do
    assert_equal 120, CardsController::SHOW_RATE_LIMIT_TO
    card = cards(:budew_pre)

    with_real_rate_limit_store do
      CardsController::INDEX_RATE_LIMIT_TO.times { get cards_path }
      get cards_path
      assert_response :too_many_requests

      CardsController::SHOW_RATE_LIMIT_TO.times do
        get card_path(card)
        assert_response :success
      end
      get card_path(card)
      assert_response :too_many_requests

      sign_in users(:one)
      get card_path(card)
      assert_response :success
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
