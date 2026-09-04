require "test_helper"

# The catalog left the `authenticate :user` block, and it is the same shape as
# DecksController#shared — a debounced field driving a paginated listing — so it gets the same
# 60/min. The event page gets none: one page load per click, no live control behind it.
class TournamentsRateLimitTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "throttles an anonymous client past the catalog limit, but never a signed-in one" do
    with_real_rate_limit_store do
      limit = TournamentsController::CATALOG_RATE_LIMIT_TO

      limit.times do
        get tournaments_path
        assert_response :success
      end

      get tournaments_path
      assert_response :too_many_requests

      # The `unless: -> { user_signed_in? }` guard: a signed-in client must sail past the same
      # limit that just stopped the anonymous one.
      sign_in users(:one)

      (limit + 1).times do
        get tournaments_path
        assert_response :success
      end
    end
  end

  test "an event page is not rationed" do
    with_real_rate_limit_store do
      (TournamentsController::CATALOG_RATE_LIMIT_TO + 5).times do
        get tournament_path(tournaments(:one))
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
