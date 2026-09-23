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

  # The archetype's front page carries its own limiter. It used to be the report and is now the
  # deck list, and the budget did not move with the report, because the amplifier that sized it
  # did not either: Turbo 8 prefetches on hover, nothing opts these links out, and the catalog
  # renders 24 of them — measured in a browser, ten hovers produced ten full page loads. So the
  # peak rate of this action is set by a cursor moving down a list, not by a click.
  test "throttles an anonymous client past the front page limit, but never a signed-in one" do
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
  test "the catalog and the front page keep separate budgets" do
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

  test "exhausting the front page's budget leaves the catalog answering" do
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

  # The report moved one level down and took a budget of its own, sized for deliberate navigation:
  # nothing hover-prefetches it in bulk any more.
  test "throttles an anonymous client past the analysis limit, but never a signed-in one" do
    with_real_rate_limit_store do
      limit = ArchetypesController::ANALYSIS_RATE_LIMIT_TO

      limit.times do
        get analysis_archetype_path(archetypes(:standings_marker))
        assert_response :success
      end

      get analysis_archetype_path(archetypes(:standings_marker))
      assert_response :too_many_requests

      sign_in users(:one)

      (limit + 1).times do
        get analysis_archetype_path(archetypes(:standings_marker))
        assert_response :success
      end
    end
  end

  # Both directions, and each spends the second budget whole, for the reason the catalog test
  # above gives: a shared name leaves one counter, and only the direction exercised second fails.
  test "the front page and the analysis keep separate budgets" do
    with_real_rate_limit_store do
      ArchetypesController::SHOW_RATE_LIMIT_TO.times { get archetype_path(archetypes(:standings_marker)) }
      get archetype_path(archetypes(:standings_marker))
      assert_response :too_many_requests

      ArchetypesController::ANALYSIS_RATE_LIMIT_TO.times do
        get analysis_archetype_path(archetypes(:standings_marker))
        assert_response :success
      end
    end
  end

  test "exhausting the analysis budget leaves the front page and the catalog answering" do
    with_real_rate_limit_store do
      ArchetypesController::ANALYSIS_RATE_LIMIT_TO.times { get analysis_archetype_path(archetypes(:standings_marker)) }
      get analysis_archetype_path(archetypes(:standings_marker))
      assert_response :too_many_requests

      ArchetypesController::SHOW_RATE_LIMIT_TO.times do
        get archetype_path(archetypes(:standings_marker))
        assert_response :success
      end
      ArchetypesController::INDEX_RATE_LIMIT_TO.times do
        get archetypes_path
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
