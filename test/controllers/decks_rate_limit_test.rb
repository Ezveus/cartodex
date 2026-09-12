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

  # #odds joined the public surface with a budget of its own, and nothing else in the suite can see
  # it: outside `with_real_rate_limit_store` the cache is :null_store and every `rate_limit` is a
  # no-op. Deleting the limiter, folding it into `name: "decks-export"` and dropping the `unless:`
  # are three separate mistakes, and this case is built to go red on each one in turn.
  test "throttles an anonymous odds page on a budget of its own, but never a signed-in one" do
    with_real_rate_limit_store do
      limit = DecksController::ODDS_RATE_LIMIT_TO

      limit.times do
        get odds_deck_path(@deck)
        assert_response :success
      end

      get odds_deck_path(@deck)
      assert_response :too_many_requests

      # A `name:` of its own, so exhausting the odds page leaves the export's budget untouched:
      # sharing one name would merge the two into a single counter this loop has already spent.
      get export_deck_path(@deck)
      assert_response :success

      # The `unless: -> { user_signed_in? }` guard: the owner reading their own build odds must
      # sail past the limit that just stopped the anonymous reader.
      sign_in users(:one)

      (limit + 1).times do
        get odds_deck_path(@deck)
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
