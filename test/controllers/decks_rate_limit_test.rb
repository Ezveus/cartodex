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

  # The proxy sheet is the one export that fans out to the image CDN, so its limit has a budget of
  # its own and, unlike every other one here, is not lifted by a session: a member looping on a
  # shared deck costs the same threads as a visitor. Members are counted per account.
  test "throttles the proxy sheet for everybody, on a budget of its own, per account once signed in" do
    with_real_rate_limit_store do
      limit = DecksController::PROXY_SHEET_RATE_LIMIT_TO
      assert_equal 10, limit

      limit.times do
        get proxy_sheet_deck_path(@deck)
        assert_response :success
      end

      # A redirect with a reason rather than the bare 429: the link is a plain download, and a
      # body-less 429 leaves the reader on a blank page.
      get proxy_sheet_deck_path(@deck)
      assert_redirected_to deck_path(@deck)
      assert_equal DecksController::PROXY_SHEET_RATE_LIMITED, flash[:alert]

      # A `name:` of its own: the export still has its whole budget. One export would not show it —
      # a shared counter at 12 is still under 30 — so the whole budget is spent.
      DecksController::EXPORT_RATE_LIMIT_TO.times do
        get export_deck_path(@deck)
        assert_response :success
      end

      # The owner is limited too, on their own counter rather than their address's.
      sign_in users(:one)
      limit.times do
        get proxy_sheet_deck_path(@deck)
        assert_response :success
      end
      get proxy_sheet_deck_path(@deck)
      assert_redirected_to deck_path(@deck)

      # Another member behind the same address has a counter of their own.
      sign_in users(:two)
      get proxy_sheet_deck_path(@deck)
      assert_response :success
    end
  end

  # #compare joined the public surface after #odds, with the same shape of budget: its own name, and
  # nothing spent by a signed-in reader.
  test "throttles an anonymous comparison on a budget of its own, but never a signed-in one" do
    path = compare_decks_path(ids: [ @deck.key, decks(:field_list).key ])

    with_real_rate_limit_store do
      limit = DecksController::COMPARE_RATE_LIMIT_TO

      limit.times do
        get path
        assert_response :success
      end

      get path
      assert_response :too_many_requests

      get odds_deck_path(@deck)
      assert_response :success

      sign_in users(:one)

      (limit + 1).times do
        get path
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
