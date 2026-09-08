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

    @original_fetch = Og::Cache.method(:fetch)
    Og::Cache.define_singleton_method(:fetch) { |_payload| "\xFF\xD8\xFF\xDB".b }
  end

  teardown do
    Og::Cache.singleton_class.remove_method(:fetch)
    Og::Cache.define_singleton_method(:fetch, @original_fetch)
  end

  # The budget applies to a signed-in member too, which is the one place this app's rate-limit
  # idiom is deliberately not followed — every other limiter carries
  # `unless: -> { user_signed_in? }`. The reasoning inverts here: those endpoints serve members,
  # this one serves crawlers, which never carry a session. Exempting members would buy legitimate
  # traffic nothing at all while lifting the cap off the only caller able to abuse a generator: a
  # member could otherwise walk /og/cards/:id across the catalogue for ~1800 renders and ~3600
  # outbound CDN fetches. Asserted rather than described, because the keyword is one word and its
  # absence is invisible.
  test "throttles an anonymous client past the limit" do
    with_real_rate_limit_store do
      limit = OgImagesController::RATE_LIMIT_TO

      limit.times do
        get deck_og_image_path(@deck.key)
        assert_response :success
      end

      get deck_og_image_path(@deck.key)
      assert_response :too_many_requests
    end
  end

  test "and throttles a signed-in member on the same budget" do
    with_real_rate_limit_store do
      sign_in users(:one)

      OgImagesController::RATE_LIMIT_TO.times do
        get deck_og_image_path(@deck.key)
        assert_response :success
      end

      get deck_og_image_path(@deck.key)
      assert_response :too_many_requests, "a member must not be exempt from a generator's budget"
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
