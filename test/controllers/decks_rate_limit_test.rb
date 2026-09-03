require "test_helper"

# DecksController#shared and #export left the `authenticate :user` block, and unlike the three
# other public surfaces they shipped with nothing bounding their rate. Mirrors the
# with_real_rate_limit_store pattern from test/controllers/cards_rate_limit_test.rb: the test
# environment's cache store is :null_store, which makes `rate_limit` a no-op, so a real store
# has to stand in for the duration of the test.
class DecksRateLimitTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @deck = decks(:one)
    @deck.update!(user: users(:one), shared: true)
  end

  test "throttles an anonymous client past the shared index limit, but never a signed-in one" do
    with_real_rate_limit_store do
      limit = DecksController::SHARED_RATE_LIMIT_TO

      limit.times do
        get shared_decks_path
        assert_response :success
      end

      get shared_decks_path
      assert_response :too_many_requests

      # The `unless: -> { user_signed_in? }` guard: a signed-in client must sail past the
      # same limit that just stopped the anonymous one.
      sign_in users(:one)

      (limit + 1).times do
        get shared_decks_path
        assert_response :success
      end
    end
  end

  test "throttles an anonymous export past its own, lower limit" do
    with_real_rate_limit_store do
      limit = DecksController::EXPORT_RATE_LIMIT_TO

      limit.times do
        get export_deck_path(@deck)
        assert_response :success
      end

      get export_deck_path(@deck)
      assert_response :too_many_requests

      # A separate `name:`, so the two limiters keep separate budgets: the index must still
      # answer after the export has been exhausted.
      get shared_decks_path
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
