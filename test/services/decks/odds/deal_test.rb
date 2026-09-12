require "test_helper"

# The keystone of the feature. Every formula in Decks::Odds::Deal is checked against exhaustive
# enumeration of *every* permutation of a small deck — 8! = 40 320 of them — in exact Rational
# arithmetic, so the assertion is equality and not agreement to some tolerance.
#
# The small deck is dealt a 3-card hand and 2 prizes rather than 7 and 6, which is why Deal takes
# hand_size: and prize_count: at all: enumerating a 60-card deck is 60! permutations, and an 8-card
# deck dealt a 7-card hand leaves one card behind and no prize block at all. The *shape* of the
# question is identical at both sizes — that is the point of the parameters.
#
# See docs/superpowers/specs/2026-09-12-deck-odds-design.md § Verification.
class Decks::Odds::DealTest < ActiveSupport::TestCase
  SMALL_N = 8
  SMALL_H = 3
  SMALL_PRIZES = 2
  # Card indices 0..7 of the small deck; 0, 1 and 2 are its Basic Pokémon.
  SMALL_BASICS = [ 0, 1, 2 ].freeze

  # Every overlap shape the page can ask for: a target disjoint from the Basics, a target that is
  # entirely Basics, a mixed target, every prize taken, and the whole deck seen. The mixed case is
  # the one that discriminates the `non_basic_copies` term — with it dropped, only this row and the
  # all-Basics rows go red.
  test "one group's accessibility equals exhaustive enumeration, for every overlap shape" do
    [
      [ [ 3 ],    0, 0, "1 copy, not a Basic" ],
      [ [ 3, 4 ], 1, 0, "2 copies, not Basics, one draw" ],
      [ [ 3, 4 ], 0, 2, "2 copies, not Basics, both prizes taken" ],
      [ [ 0 ],    0, 0, "1 copy, and it is a Basic" ],
      [ [ 0, 1 ], 1, 1, "2 copies, both Basics" ],
      [ [ 0, 3 ], 1, 1, "2 copies, mixed: one Basic, one not" ],
      [ [ 3 ],    0, 2, "1 copy, every prize taken" ],
      [ [ 3 ],    3, 2, "1 copy, the whole deck seen" ]
    ].each do |target, draws, taken, label|
      copies, non_basic_copies = bucket_for(target)

      assert_equal enumerate(targets: [ target ], draws: draws, taken: taken),
        small_deal.accessible(copies: copies, non_basic_copies: non_basic_copies, seen: draws + taken),
        label
    end
  end

  # Inclusion-exclusion over disjoint buckets. Disjointness is what lets |U_S| be a sum rather than a
  # set union, which is why Decks::Odds::Combo enforces it twice over.
  test "an AND of OR-buckets equals exhaustive enumeration" do
    [
      [ [ [ 3 ], [ 4 ] ],        0, 0, "2 buckets, neither holding a Basic" ],
      [ [ [ 3 ], [ 4 ] ],        1, 1, "2 buckets, one draw and one prize" ],
      [ [ [ 0 ], [ 3 ] ],        1, 0, "2 buckets, one of them a Basic" ],
      [ [ [ 0 ], [ 3 ], [ 4 ] ], 0, 2, "3 buckets, every prize taken" ],
      [ [ [ 0, 1 ], [ 3, 4 ] ],  1, 1, "2 buckets of 2, one of them all Basics" ]
    ].each do |targets, draws, taken, label|
      assert_equal enumerate(targets: targets, draws: draws, taken: taken),
        small_deal.all_buckets(buckets: targets.map { |target| bucket_for(target) }, seen: draws + taken),
        label
    end
  end

  # The 60-card reference table from the design's § The measurements. Mean mulligans is m/(1-m):
  # each redeal is independent, so the count before a keepable hand is geometric.
  test "the mulligan rate and the mean mulligans match the 60-card reference table" do
    {
       8 => [ "34.64", "0.530" ],
      10 => [ "25.86", "0.349" ],
      12 => [ "19.06", "0.236" ],
      14 => [ "13.86", "0.161" ],
      16 => [ "9.92",  "0.110" ],
      18 => [ "6.99",  "0.075" ]
    }.each do |basics, (rate, mean)|
      deal = Decks::Odds::Deal.new(deck_size: 60, basics: basics)

      assert_equal rate, format("%.2f", deal.mulligan_rate * 100), "mulligan rate at #{basics} Basics"
      assert_equal mean, format("%.3f", deal.mean_mulligans), "mean mulligans at #{basics} Basics"
    end
  end

  # The single strongest reason this model is conditional and not a naive `7 of 60` table: the gap
  # reaches 9.41 points, and it reaches it on exactly the card a player cares most about — the
  # four-of Basic they want to start with. A naive table tells them it shows up in 39.95 % of
  # opening hands when it really shows up in 49.36 %.
  test "the conditional answer differs from the naive one by up to 9.41 points" do
    deal = Decks::Odds::Deal.new(deck_size: 60, basics: 12)

    [
      [ 4, false, "39.95", "38.06" ],
      [ 3, false, "31.54", "29.94" ],
      [ 1, false, "11.67", "10.98" ],
      [ 1, true,  "11.67", "14.41" ],
      [ 3, true,  "31.54", "38.97" ],
      [ 4, true,  "39.95", "49.36" ]
    ].each do |copies, basic, naive, conditional|
      label = "#{copies} copies, #{basic ? "a Basic" : "not a Basic"}"

      assert_equal naive, format("%.2f", naive_opening(copies) * 100), "naive, #{label}"
      assert_equal conditional,
        format("%.2f", deal.accessible(copies: copies, non_basic_copies: basic ? 0 : copies, seen: 0) * 100),
        "conditional, #{label}"
    end
  end

  # Prize risk is deliberately *not* conditioned on the mulligan: which cards sit in the prize block
  # is a fact about positions 8..13, and the mulligan condition touches the hand alone. The "all
  # prized" column is why singletons get a panel of their own — a 1-of is unreachable 10 % of the
  # time and a 2-of 0.847 %, two orders of magnitude apart.
  test "prize risk matches the 60-card reference table" do
    deal = Decks::Odds::Deal.new(deck_size: 60, basics: 12)

    {
      1 => [ "10.00", "10.000" ],
      2 => [ "19.15", "0.847" ],
      3 => [ "27.52", "0.058" ],
      4 => [ "35.15", "0.003" ]
    }.each do |copies, (at_least_one, all)|
      assert_equal at_least_one, format("%.2f", deal.at_least_one_prized(copies: copies) * 100),
        "at least one of #{copies} prized"
      assert_equal all, format("%.3f", deal.all_prized(copies: copies) * 100),
        "all #{copies} prized"
    end
  end

  # The sentence a merged "+X cards gained" control could not say, and the reason prizes keep their
  # own axis even though `d` and `p` are mathematically interchangeable.
  test "a one-of becomes reachable as its prizes are taken" do
    deal = Decks::Odds::Deal.new(deck_size: 60, basics: 12)

    assert_equal %w[10.00 8.33 6.67 5.00 3.33 1.67 0.00],
      (0..6).map { |taken| format("%.2f", deal.all_prized(copies: 1, taken: taken) * 100) }
  end

  # The two states where the model has nothing to say. A deck with no Basic Pokémon never terminates
  # its mulligan loop, so every conditional probability is 0/0; a deck too small to deal a hand and
  # six prizes divides by C(N, 7) = 0. Both are reachable from the UI — the second is every deck in
  # the minute after it is created — so they raise rather than answering a nil that would format as
  # "0.00 %".
  test "a deck that cannot start a game refuses to answer" do
    no_basics = Decks::Odds::Deal.new(deck_size: 60, basics: 0)
    too_small = Decks::Odds::Deal.new(deck_size: 3, basics: 2)

    assert_not no_basics.playable?
    assert_not too_small.playable?

    assert_raises(Decks::Odds::Deal::Unplayable) { no_basics.mulligan_rate }
    assert_raises(Decks::Odds::Deal::Unplayable) { too_small.mulligan_rate }
    assert_raises(Decks::Odds::Deal::Unplayable) do
      no_basics.accessible(copies: 4, non_basic_copies: 4, seen: 3)
    end
  end

  # A deck of 7 to 12 cards deals a hand and no prizes. Report is what passes prize_count: 0 there;
  # this asserts that Deal accepts it rather than dividing by C(0, p).
  test "a deck too small for prizes still deals a hand" do
    deal = Decks::Odds::Deal.new(deck_size: 10, basics: 4, prize_count: 0)

    assert deal.playable?
    assert_equal 3, deal.max_seen
    assert_equal 3, deal.max_draws
    assert_equal Rational(0), deal.at_least_one_prized(copies: 2)
    assert_equal Rational(0), deal.all_prized(copies: 2)
  end

  # The two ceilings the scenario controls clamp against, and the reason they are two: p <= 6 while
  # d <= 47, so a merged control could clamp neither. 53 is also the length of every curve Report
  # precomputes, indices 0..53.
  test "the two axes have different ceilings" do
    deal = Decks::Odds::Deal.new(deck_size: 60, basics: 12)

    assert_equal 53, deal.max_seen
    assert_equal 47, deal.max_draws
  end

  # The zero-denominator guard, which is the only thing in the file holding an out-of-range argument
  # off a ZeroDivisionError on a page. Every case above stays inside 0..max_seen and 0..prize_count,
  # so without this one the guard could be deleted and the file would stay green. Both calls below
  # reach a C(n, k) that is zero in a denominator: `taken` past the prize block, and `seen` past the
  # cards outside the hand. Answering 0 there is also correct — you cannot avoid what you have
  # already seen all of.
  test "an argument past its clamp answers zero rather than dividing by zero" do
    deal = Decks::Odds::Deal.new(deck_size: 60, basics: 12)

    assert_equal Rational(0), deal.all_prized(copies: 1, taken: 7)
    assert_nothing_raised { deal.accessible(copies: 4, non_basic_copies: 4, seen: deal.max_seen + 1) }
  end

  private

  def small_deal
    Decks::Odds::Deal.new(
      deck_size: SMALL_N, basics: SMALL_BASICS.size, hand_size: SMALL_H, prize_count: SMALL_PRIZES
    )
  end

  # A target's [copies, non_basic_copies] — the shape Deal takes a bucket in.
  def bucket_for(target)
    [ target.size, (target - SMALL_BASICS).size ]
  end

  # P(at least one card of every bucket is accessible | the hand was keepable), by walking every
  # permutation of the deck and every choice of which prizes were taken. The slow, obviously correct
  # answer, and the only thing in this file that does not go through Deal.
  def enumerate(targets:, draws:, taken:)
    hand_positions  = (0...SMALL_H).to_a
    prize_positions = (SMALL_H...(SMALL_H + SMALL_PRIZES)).to_a
    draw_positions  = ((SMALL_H + SMALL_PRIZES)...(SMALL_H + SMALL_PRIZES + draws)).to_a
    taken_choices   = prize_positions.combination(taken).to_a

    kept = 0
    hit = 0

    (0...SMALL_N).to_a.permutation do |permutation|
      hand = hand_positions.map { |position| permutation[position] }
      next if (hand & SMALL_BASICS).empty? # a mulligan: this deal is never kept

      taken_choices.each do |prizes|
        kept += 1
        accessible = hand +
                     draw_positions.map { |position| permutation[position] } +
                     prizes.map { |position| permutation[position] }
        hit += 1 if targets.all? { |target| (accessible & target).any? }
      end
    end

    Rational(hit, kept)
  end

  # The table this feature exists to replace: "at least one of `copies` among 7 of 60", with no
  # regard for whether the hand was keepable. Spelled out here rather than borrowed from Deal, since
  # the point of the assertion is that two different formulas disagree.
  def naive_opening(copies)
    1 - Rational(combinations(60 - copies, 7), combinations(60, 7))
  end

  def combinations(n, k)
    (0...k).reduce(1) { |product, i| product * (n - i) / (i + 1) }
  end
end
