require "test_helper"
require "tmpdir"

# Mirrors CardsRateLimitTest and ArchetypesRateLimitTest, including the with_real_rate_limit_store
# pattern: the test environment's cache store is :null_store, which makes `rate_limit` a silent
# no-op. Without this file the limiter could be absent, mis-numbered, or split into three, and
# nothing anywhere would notice.
#
# The interesting half is the inverse of ArchetypesRateLimitTest's "the catalog and the report keep
# separate budgets": here the three actions deliberately *share* one, because a cold request costs
# the same two CDN fetches whichever kind it is, and the budget is meant to cap that cost rather
# than to be fair between kinds.
class OgImagesRateLimitTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @deck = decks(:one)
    @deck.update!(user: users(:one), shared: true)
    @archetype = archetypes(:standings_marker)

    @dir = Dir.mktmpdir
    file = File.join(@dir, "stub.jpg")
    File.binwrite(file, "\xFF\xD8\xFF\xDB".b)
    @original_fetch = Og::Cache.method(:fetch)
    Og::Cache.define_singleton_method(:fetch) { |_payload| Pathname.new(file) }
  end

  teardown do
    Og::Cache.singleton_class.remove_method(:fetch)
    Og::Cache.define_singleton_method(:fetch, @original_fetch)
    FileUtils.remove_entry(@dir)
  end

  test "throttles an anonymous client past the limit, but never a signed-in one" do
    with_real_rate_limit_store do
      limit = OgImagesController::RATE_LIMIT_TO

      limit.times do
        get deck_og_image_path(@deck.key)
        assert_response :success
      end

      get deck_og_image_path(@deck.key)
      assert_response :too_many_requests

      sign_in users(:one)

      (limit + 1).times do
        get deck_og_image_path(@deck.key)
        assert_response :success
      end
    end
  end

  # One bucket for the three actions. Exhausting it on #deck must also stop #archetype — the
  # opposite of what the app's other two-limiter controller asserts, and the only assertion that
  # can tell one shared `name:` from three distinct ones. Sabotage check: give the three actions
  # three names and this goes red on the first archetype request.
  test "the three kinds share one budget" do
    with_real_rate_limit_store do
      OgImagesController::RATE_LIMIT_TO.times { get deck_og_image_path(@deck.key) }

      get deck_og_image_path(@deck.key)
      assert_response :too_many_requests

      get archetype_og_image_path(@archetype.slug)
      assert_response :too_many_requests

      get card_og_image_path(cards(:doublade).id)
      assert_response :too_many_requests
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
