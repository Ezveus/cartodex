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

  # The report carries its own limiter, and this test is the inversion of the one that pinned its
  # *absence* — which would have stayed green after the rule changed, since it looped only
  # INDEX_RATE_LIMIT_TO + 5 requests and the new budget is twice that.
  #
  # Higher than the catalog's 60 rather than lower, and that reads backwards until the amplifier
  # is named: Turbo 8 prefetches on hover, nothing opts these links out, and the catalog renders
  # 24 of them — measured in a browser, ten hovers produced ten full report loads. So the peak
  # rate of this action is set by a cursor moving down a list, not by a click, while the catalog's
  # is bounded by a 300 ms debounce and its own Turbo Frame short-circuit.
  test "throttles an anonymous client past the report limit, but never a signed-in one" do
    with_real_rate_limit_store do
      limit = ArchetypesController::SHOW_RATE_LIMIT_TO

      limit.times do
        get archetype_path(archetypes(:standings_marker))
        assert_response :success
      end

      get archetype_path(archetypes(:standings_marker))
      assert_response :too_many_requests

      sign_in users(:one)

      (limit + 1).times do
        get archetype_path(archetypes(:standings_marker))
        assert_response :success
      end
    end
  end

  # The `name:` earns its keep now that a second limiter has landed on this controller: Rails keys
  # a limiter on ["rate-limit", scope, name, by] with `scope` defaulting to controller_path, so
  # without distinct names the two actions would share one budget and a reader who exhausted the
  # catalog could not open a report. Asserted in both directions, because one name shared by two
  # limiters fails only in whichever direction is exercised second.
  test "the catalog and the report keep separate budgets" do
    with_real_rate_limit_store do
      ArchetypesController::INDEX_RATE_LIMIT_TO.times { get archetypes_path }

      get archetypes_path
      assert_response :too_many_requests

      # The report's **whole** budget, not one request into it, and that is what makes this
      # assertion discriminate rather than merely describe: sharing one `name:` would leave a
      # single counter sitting at 61, which is under the report's 120, so a one-request check
      # passes over the bug. Sabotaged both ways — with the names collapsed, this goes red on the
      # 60th of these and the test below goes red on its first catalog request.
      ArchetypesController::SHOW_RATE_LIMIT_TO.times do
        get archetype_path(archetypes(:standings_marker))
        assert_response :success
      end
    end
  end

  test "exhausting the report's budget leaves the catalog answering" do
    with_real_rate_limit_store do
      ArchetypesController::SHOW_RATE_LIMIT_TO.times do
        get archetype_path(archetypes(:standings_marker))
      end

      get archetype_path(archetypes(:standings_marker))
      assert_response :too_many_requests

      get archetypes_path
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
