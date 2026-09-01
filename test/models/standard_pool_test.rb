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

  # Nothing reads the marks yet, which is the whole reason the shape is enforced here:
  # a "H I J" that slipped through the admin screen's parser would sit unnoticed until
  # #27 or #61 read it, and would then be wrong somewhere far from where it was typed.
  test "a mark that is not a single uppercase letter is refused" do
    pool = StandardPool.new(
      first_card_set: card_sets(:asc), last_card_set: card_sets(:por),
      regulation_marks: [ "H", "I J" ],
      released_on: Date.new(2026, 6, 1), legal_on: Date.new(2026, 6, 15)
    )

    assert_not pool.valid?
    assert_includes pool.errors[:regulation_marks].join, "single uppercase letter"
  end

  test "a marks value that is not a list at all is refused" do
    pool = StandardPool.new(
      first_card_set: card_sets(:asc), last_card_set: card_sets(:por),
      regulation_marks: "H",
      released_on: Date.new(2026, 6, 1), legal_on: Date.new(2026, 6, 15)
    )

    assert_not pool.valid?
    assert_includes pool.errors[:regulation_marks].join, "list of single-letter marks"
  end

  # Legality follows existence. The admin screen can type either date, and the pair is
  # nonsense a future legality consumer would trust: at(date) would name a pool whose
  # cards did not exist on that date.
  test "a pool legal before its cards released is refused" do
    pool = StandardPool.new(
      first_card_set: card_sets(:asc), last_card_set: card_sets(:por),
      regulation_marks: %w[H I J],
      released_on: Date.new(2026, 6, 1), legal_on: Date.new(2026, 5, 15)
    )

    assert_not pool.valid?
    assert_includes pool.errors[:legal_on].join, "before the release date"
  end

  # A pool born from a rotation with no set release is legal the day its cards are
  # already out — SVI-JTG is exactly that — so equality has to pass.
  test "a pool legal on its release date is accepted" do
    pool = StandardPool.new(
      first_card_set: card_sets(:asc), last_card_set: card_sets(:por),
      regulation_marks: %w[H I J],
      released_on: Date.new(2026, 6, 1), legal_on: Date.new(2026, 6, 1)
    )

    assert_predicate pool, :valid?
  end

  # Future-dated on purpose: a pool announced before its cards exist is legitimate, and
  # `current` is what keeps it from becoming the default anchor. A "no future dates"
  # validation would forbid the seed's own forward-looking rows.
  test "a future-dated pool is valid" do
    pool = StandardPool.new(
      first_card_set: card_sets(:asc), last_card_set: card_sets(:por),
      regulation_marks: %w[H I J],
      released_on: Date.current + 30, legal_on: Date.current + 44
    )

    assert_predicate pool, :valid?
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
  # released_on carries no uniqueness constraint and the admin screen is maintained by hand, so
  # two pools can share one. Without a tiebreaker `current` picks arbitrarily and can pick the
  # other one on the next request, leaving a form's pre-selection and the stale-anchor notice
  # disagreeing between two loads of the same page.
  test "current is deterministic when two pools share a release date" do
    tail = CardSet.create!(code: "ZZZ", name: "Zed Zone", release_date: Date.new(2026, 2, 1))
    shared = { regulation_marks: %w[H I J], released_on: Date.new(2026, 2, 1), legal_on: Date.new(2026, 2, 15) }
    a = StandardPool.create!(first_card_set: card_sets(:asc), last_card_set: tail, **shared)
    b = StandardPool.create!(first_card_set: card_sets(:twm), last_card_set: tail, **shared)

    winner = [ a, b ].max_by(&:id)

    assert_equal winner, StandardPool.current
    assert_equal winner, StandardPool.current # same answer twice, not a coin flip
  end

  test "at is deterministic when two pools share a legality date" do
    tail = CardSet.create!(code: "ZZZ", name: "Zed Zone", release_date: Date.new(2026, 2, 1))
    shared = { regulation_marks: %w[H I J], released_on: Date.new(2026, 2, 1), legal_on: Date.new(2026, 2, 15) }
    a = StandardPool.create!(first_card_set: card_sets(:asc), last_card_set: tail, **shared)
    b = StandardPool.create!(first_card_set: card_sets(:twm), last_card_set: tail, **shared)

    winner = [ a, b ].max_by(&:id)

    assert_equal winner, StandardPool.at(Date.new(2026, 3, 1))
    assert_equal winner, StandardPool.at(Date.new(2026, 3, 1))
  end

  # The admin form lists the same collection in both selects, so inverting them is one click.
  # The result passes every other validation and, if its released_on is recent, becomes
  # StandardPool.current — the default anchor of every new deck and every import.
  test "refuses bounds whose releases run backwards" do
    inverted = StandardPool.new(
      first_card_set: card_sets(:por), last_card_set: card_sets(:asc),
      regulation_marks: %w[H I J], released_on: Date.new(2026, 2, 1), legal_on: Date.new(2026, 2, 15)
    )

    assert_not inverted.valid?
    assert_includes inverted.errors[:last_card_set], "must not be released before the lower bound"
  end

  test "accepts bounds released on the same day" do
    same_day = CardSet.create!(code: "ZZZ", name: "Zed Zone", release_date: card_sets(:asc).release_date)
    pool = StandardPool.new(
      first_card_set: card_sets(:asc), last_card_set: same_day,
      regulation_marks: %w[H I J], released_on: Date.new(2026, 2, 1), legal_on: Date.new(2026, 2, 15)
    )

    assert pool.valid?, pool.errors.full_messages.to_sentence
  end

  # A set imported before the importer learned to record a release date has a NULL one.
  # Refusing the pool then would block a legitimate row over a fact we do not have.
  test "stays silent when a bound has no release date" do
    undated = CardSet.create!(code: "ZZZ", name: "Zed Zone")
    pool = StandardPool.new(
      first_card_set: undated, last_card_set: card_sets(:asc),
      regulation_marks: %w[H I J], released_on: Date.new(2026, 2, 1), legal_on: Date.new(2026, 2, 15)
    )

    assert pool.valid?, pool.errors.full_messages.to_sentence
  end
end
