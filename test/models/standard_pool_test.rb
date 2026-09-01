require "test_helper"

class StandardPoolTest < ActiveSupport::TestCase
  test "is named by its two bounds, oldest legal set first" do
    assert_equal "TWM-POR", standard_pools(:twm_por).name
  end

  test "current is the most recently released pool" do
    assert_equal standard_pools(:twm_por), StandardPool.current
  end

  # The moment an announced-but-unreleased set's pool is seeded, it must not
  # become the default anchor for new decks before its date.
  test "current ignores a pool whose released_on is in the future" do
    StandardPool.create!(
      first_card_set: card_sets(:asc), last_card_set: card_sets(:por),
      regulation_marks: %w[H I J],
      released_on: Date.current + 1, legal_on: Date.current + 15
    )

    assert_equal standard_pools(:twm_por), StandardPool.current
  end

  # A tournament asks what was legal on its date, which is legal_on and not
  # released_on: a set is tournament-legal about two weeks after it releases.
  test "at reads legal_on, not released_on" do
    between = Date.new(2026, 1, 20) # after twm_por released, before it was legal

    assert_equal standard_pools(:twm_asc), StandardPool.at(between)
    assert_equal standard_pools(:twm_por), StandardPool.at(Date.new(2026, 1, 30))
  end

  test "at is nil before the oldest pool was legal" do
    assert_nil StandardPool.at(Date.new(2020, 1, 1))
  end

  test "the bound pair is unique" do
    duplicate = StandardPool.new(
      first_card_set: card_sets(:twm), last_card_set: card_sets(:por),
      regulation_marks: %w[G H I J],
      released_on: Date.new(2026, 2, 1), legal_on: Date.new(2026, 2, 15)
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:first_card_set_id], "has already been taken"
  end

  test "the database refuses a duplicate bound pair even without validations" do
    duplicate = StandardPool.new(
      first_card_set: card_sets(:twm), last_card_set: card_sets(:por),
      regulation_marks: %w[G H I J],
      released_on: Date.new(2026, 2, 1), legal_on: Date.new(2026, 2, 15)
    )

    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save(validate: false) }
  end

  test "regulation_marks round-trips as an array of strings" do
    assert_equal %w[G H I J], standard_pools(:twm_por).regulation_marks
  end

  # Within one rotation era the lower bound is constant and the upper bound only
  # advances, and each rotation changes the lower bound — which is what makes the
  # bound pair a safe unique key across the whole history.
  test "a pool with a lower bound the seed has no card set for cannot be written" do
    orphan = StandardPool.new(
      first_card_set: nil, last_card_set: card_sets(:por),
      regulation_marks: %w[H I J],
      released_on: Date.new(2026, 3, 27), legal_on: Date.new(2026, 4, 10)
    )

    assert_not orphan.valid?
    assert_includes orphan.errors[:first_card_set], "must exist"
  end

  # :nullify would leave the deck with a NULL anchor, which its own validation
  # then refuses on the next edit.
  #
  # This pool's fixtures hold both decks and tournaments, but the error only names
  # "decks": destroy runs dependent callbacks in declaration order and the first
  # restriction found aborts the chain, so the :tournaments check never runs.
  # Harmless — both associations restrict the destroy either way — but it does mean
  # reordering the two in the model would swap which noun shows up in the message.
  test "a pool holding decks refuses to be destroyed" do
    pool = standard_pools(:twm_por)

    assert_not pool.destroy
    assert_includes pool.errors[:base].join, "decks"
    assert StandardPool.exists?(pool.id)
  end
end
