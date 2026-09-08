require "test_helper"

# ArchetypesController#index went public and picked up a per-IP limiter for exactly that reason —
# nothing before this could exercise it, since no anonymous request could reach the route at all.
# Mirrors CardsRateLimitTest, including the with_real_rate_limit_store pattern: the test
# environment's cache store is :null_store, which makes `rate_limit` a silent no-op.
class ArchetypesRateLimitTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "throttles an anonymous client past the index limit, but never a signed-in one" do
    with_real_rate_limit_store do
      limit = ArchetypesController::INDEX_RATE_LIMIT_TO

      limit.times do
        get archetypes_path
        assert_response :success
      end

      get archetypes_path
      assert_response :too_many_requests

      # The `unless: -> { user_signed_in? }` guard: a signed-in client is exempt, so it must sail
      # past the same limit that just stopped the anonymous client above.
      sign_in users(:one)

      (limit + 1).times do
        get archetypes_path
        assert_response :success
      end
    end
  end

  # The other half of the decision, and the half only a test can hold down: an archetype's report
  # carries no limiter. Its two selects auto-submit, so a click there is a full page load of 13
  # queries — but that is one request per deliberate click and not one per keystroke, which is
  # the line decks#show and tournaments#show sit on the same side of. A separate `name:` is what
  # makes this true even after the catalog's budget is spent.
  test "an archetype page is not rationed" do
    with_real_rate_limit_store do
      (ArchetypesController::INDEX_RATE_LIMIT_TO + 5).times do
        get archetype_path(archetypes(:standings_marker))
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
