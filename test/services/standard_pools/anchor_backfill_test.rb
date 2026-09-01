require "test_helper"

class StandardPools::AnchorBackfillTest < ActiveSupport::TestCase
  setup do
    # The fixtures are already anchored, which is the post-migration state. Undo
    # that to reproduce the pre-migration one.
    Deck.update_all(standard_pool_id: nil)
    Tournament.update_all(standard_pool_id: nil)
  end

  # created_at is not the date a deck was built — importing an old decklist today
  # stamps today — so anchoring on it would fabricate a precision the column has
  # not got. The current pool is visibly wrong for an old deck rather than
  # plausibly wrong, and the stale-anchor nudge invites the user to fix it.
  test "anchors standard decks to the current pool" do
    result = StandardPools::AnchorBackfill.call

    assert_equal StandardPool.current, decks(:one).reload.standard_pool
    assert_equal 2, result.decks
  end

  test "anchors tournaments to the pool legal on their date" do
    tournaments(:one).update_columns(date: Date.new(2026, 1, 20))

    StandardPools::AnchorBackfill.call

    # 2026-01-20 is after twm_por released but before it was legal.
    assert_equal standard_pools(:twm_asc), tournaments(:one).reload.standard_pool
  end

  # NULL is unsavable on the next edit, so an event older than the whole seeded
  # history falls back to the oldest pool rather than staying empty.
  test "a tournament older than the oldest pool falls back to the oldest" do
    tournaments(:one).update_columns(date: Date.new(2019, 1, 1))

    StandardPools::AnchorBackfill.call

    assert_equal standard_pools(:twm_asc), tournaments(:one).reload.standard_pool
  end

  test "leaves rows whose format is not standard alone" do
    decks(:one).update_columns(format: "glc")

    StandardPools::AnchorBackfill.call

    assert_nil decks(:one).reload.standard_pool_id
  end

  test "is idempotent and does not move an anchor already set" do
    decks(:one).update_columns(standard_pool_id: standard_pools(:twm_asc).id)

    result = StandardPools::AnchorBackfill.call

    assert_equal standard_pools(:twm_asc), decks(:one).reload.standard_pool
    assert_equal 1, result.decks
  end

  test "reports rather than writes when there is no pool at all" do
    Deck.update_all(standard_pool_id: nil)
    Tournament.update_all(standard_pool_id: nil)
    StandardPool.delete_all

    result = StandardPools::AnchorBackfill.call

    assert_equal 0, result.decks
    assert_includes result.skipped.join, "no Standard pool"
  end

  # The empty-table guard does not cover this: `oldest` is ordered by legal_on and is a
  # real row, so the run proceeded and wrote StandardPool.current — nil — over every
  # unanchored deck, while still returning the row count update_all touched. The task
  # then printed "Anchored N deck(s)" having anchored none.
  test "reports rather than blanks the decks when every pool is future-dated" do
    StandardPool.update_all(released_on: Date.current + 30)

    result = StandardPools::AnchorBackfill.call

    assert_equal 0, result.decks
    assert_nil decks(:one).reload.standard_pool_id
    assert_includes result.skipped.join, "no Standard pool has released yet"
  end

  # Tournaments read legal_on, which a future released_on does not touch, so they are
  # still anchorable in that state and must not be skipped along with the decks.
  test "still anchors tournaments when every pool is future-dated" do
    StandardPool.update_all(released_on: Date.current + 30)

    result = StandardPools::AnchorBackfill.call

    assert_equal 2, result.tournaments
    assert_not_nil tournaments(:one).reload.standard_pool_id
  end
  # The fallback is a guess, and the scope filters on a NULL anchor — so seeding the missing
  # older pool and re-running will never revisit it. Naming it is the only chance an operator
  # gets to fix it by hand.
  test "a tournament older than every pool is anchored and named as approximate" do
    tournaments(:one).update_columns(date: Date.new(2019, 1, 1))

    result = StandardPools::AnchorBackfill.call

    assert_equal standard_pools(:twm_asc), tournaments(:one).reload.standard_pool
    assert_equal 1, result.approximated.size
    assert_match(/Regional Championship/, result.approximated.first)
    assert_match(/2019-01-01/, result.approximated.first)
  end

  # The other half: a tournament whose date a pool genuinely covers is not reported, or the
  # list would name every row and mean nothing.
  test "a tournament a pool covers is not reported as approximate" do
    tournaments(:one).update_columns(date: Date.new(2026, 2, 1))

    result = StandardPools::AnchorBackfill.call

    assert_equal standard_pools(:twm_por), tournaments(:one).reload.standard_pool
    assert_empty result.approximated
  end
end
