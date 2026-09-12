require "test_helper"

# The page payload. Nothing here re-derives a probability: every assertion below compares what the
# report publishes against what Decks::Odds::Deal answers for the same question, because a report
# that computed its own version of a number would be a second implementation of the model.
class Decks::Odds::ReportTest < ActiveSupport::TestCase
  setup do
    @deck = decks(:one)
    @deck.deck_cards.destroy_all
  end

  # 60 cards, 12 of them Basic Pokémon — the shape every reference number in the design was measured
  # on. Six distinct names, so a `find` by name below is never ambiguous, and the two Budew printings
  # are here to make the fingerprint grouping observable.
  def build_reference_deck
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 4)              # Basic
    @deck.deck_cards.create!(card: cards(:teal_mask_ogerpon_ex), quantity: 4) # Basic
    @deck.deck_cards.create!(card: cards(:budew_pre), quantity: 2)            # Basic
    @deck.deck_cards.create!(card: cards(:budew_asc), quantity: 2)            # Basic, same group
    @deck.deck_cards.create!(card: cards(:bosss_orders_meg), quantity: 4)     # Trainer
    @deck.deck_cards.create!(card: cards(:doublade), quantity: 4)             # Stage 1, not a Basic
    @deck.deck_cards.create!(card: cards(:basic_psychic_energy), quantity: 40)
    @deck.reload
  end

  def reference_deal = Decks::Odds::Deal.new(deck_size: 60, basics: 12)

  test "the aggregates are exactly what Deal answers for the same deck" do
    build_reference_deck
    report = Decks::Odds::Report.call(@deck)

    assert report.playable?
    assert_equal 60, report.deck_size
    assert_equal 12, report.basics
    assert_equal 7, report.hand_size
    assert_equal Decks::Odds::Report.percent(reference_deal.mulligan_rate), report.mulligan_rate_percent
    assert_equal 19.06, report.mulligan_rate_percent
    assert_equal 0.236, report.mean_mulligans
    assert_equal 47, report.max_draws
    assert_equal 53, report.max_seen
    assert_equal Decks::Odds::Report::DEFAULT_TURN, report.default_seen
    assert_equal 4, report.entries_by_key["budew_shared"].copies
    assert report.prizes?
    assert report.reference_size?
  end

  # One curve per group, indexed by `a_rest` from 0 to max_seen — 54 points on a 60-card deck. The
  # three scenario steppers move one index between them, which is the whole reason a reactive page
  # needs no arithmetic in JavaScript.
  test "each card row carries a curve over every reachable scenario" do
    build_reference_deck
    report = Decks::Odds::Report.call(@deck)
    deal = reference_deal

    row = report.card_rows.find { |r| r.name == "Teal Mask Ogerpon ex" }

    assert_equal 4, row.copies
    assert_equal 54, row.accessible_curve.size
    assert_equal Decks::Odds::Report.percent(deal.accessible(copies: 4, non_basic_copies: 0, seen: 0)),
      row.accessible_curve.first
    assert_equal 49.36, row.accessible_curve.first, "a four-of Basic, conditional on a keepable hand"
    assert_equal row.accessible_curve.first, row.opening,
      "the opening-hand column is the seen = 0 point of the same curve"
    assert_equal Decks::Odds::Report.percent(deal.accessible(copies: 4, non_basic_copies: 0, seen: 12)),
      row.accessible_curve[12]
    assert_equal 100.0, row.accessible_curve.last, "seeing every card outside the hand is certainty"
  end

  # A Trainer is not a Basic, so its curve must carry non_basic_copies = copies. Dropping that term
  # moves this row by 11.30 points at seen = 0 and leaves the Pokémon row above untouched, which is
  # why both are asserted.
  test "a non-Basic group is computed with its copies counted as non-Basic" do
    build_reference_deck
    report = Decks::Odds::Report.call(@deck)

    row = report.card_rows.find { |r| r.name == "Boss's Orders" }

    assert_equal 4, row.copies
    assert_equal Decks::Odds::Report.percent(
      reference_deal.accessible(copies: 4, non_basic_copies: 4, seen: 0)
    ), row.opening
    assert_equal 38.06, row.opening
  end

  # The order the table is printed in, asserted whole. Every other assertion in this file reaches a
  # row through `find`, which any order satisfies, so this is the only test that can see the sort at
  # all. The reference deck is a five-way tie at 4 copies behind one 40-card group, which makes both
  # halves of the key load-bearing: drop the sign and the Energy falls to the bottom, drop the name
  # and the five tied groups come back in the order they were typed.
  test "card rows are ordered by copies, ties broken by name" do
    build_reference_deck
    report = Decks::Odds::Report.call(@deck)

    assert_equal [ "Psychic Energy", "Boss's Orders", "Budew", "Doublade", "Honedge",
                   "Teal Mask Ogerpon ex" ],
      report.card_rows.map(&:name)
    assert_equal [ 40, 4, 4, 4, 4, 4 ], report.card_rows.map(&:copies)
  end

  # The two Budew printings are one group of four, which is what both the rules and the
  # probabilities say.
  test "two printings of one card are one row" do
    build_reference_deck
    report = Decks::Odds::Report.call(@deck)

    budew = report.card_rows.select { |row| row.name == "Budew" }

    assert_equal 1, budew.size
    assert_equal 4, budew.first.copies
    assert_equal "budew_shared", budew.first.key
  end

  # The prize columns answer a question about the prize block itself rather than about
  # accessibility, so they are indexed by prizes taken alone — seven points, not fifty-four.
  test "the prize curve is indexed by prizes taken" do
    build_reference_deck
    report = Decks::Odds::Report.call(@deck)

    row = report.card_rows.find { |r| r.name == "Budew" }

    assert_equal 7, row.all_prized_curve.size
    assert_equal 35.15, row.at_least_one_prized
    assert_equal 0.0, row.all_prized_curve.last, "nothing is still prized once every prize is taken"
  end

  # Groups ordered by the chance that every copy is unreachable, most at risk first. The panel is
  # capped, since on a real deck it would otherwise restate the whole table in a different order.
  test "the prize panel leads with the groups most at risk" do
    build_reference_deck
    @deck.deck_cards.find_by(card: cards(:basic_psychic_energy)).update!(quantity: 39)
    @deck.deck_cards.create!(card: cards(:froakie_cri), quantity: 1)

    report = Decks::Odds::Report.call(@deck.reload)
    risks = report.prize_rows.map { |row| row.all_prized_curve.first }

    assert_equal 60, report.deck_size
    assert_equal "Froakie", report.prize_rows.first.name, "the one-of is the most at risk"
    assert_equal 10.0, risks.first
    assert_operator report.prize_rows.size, :<=, Decks::Odds::Report::PRIZE_PANEL_SIZE
    assert_equal risks.sort.reverse, risks, "ordered by the chance every copy is unreachable"
  end

  # One row per role in the deck, counting copies. A card carrying two roles is counted under both,
  # exactly as Archetypes::CardReport does — which is why the panel prints a sentence saying the
  # sections do not add up to a list.
  test "a role row sums the copies of every card carrying it" do
    draw = CardLabel.create!(slug: "draw", name: "Draw", family: "role", position: 10)
    gust = CardLabel.create!(slug: "gust", name: "Gust", family: "role", position: 30)
    CardLabelAssignment.create!(card_label: draw, fingerprint: "bosss_orders_meg_fp",
                                card: cards(:bosss_orders_meg), source: "curated")
    CardLabelAssignment.create!(card_label: gust, fingerprint: "bosss_orders_meg_fp",
                                card: cards(:bosss_orders_meg), source: "curated")
    CardLabelAssignment.create!(card_label: draw, fingerprint: "honedge_fp",
                                card: cards(:honedge), source: "curated")

    build_reference_deck
    report = Decks::Odds::Report.call(@deck)

    draw_row = report.role_rows.find { |row| row.slug == "draw" }
    gust_row = report.role_rows.find { |row| row.slug == "gust" }

    assert_equal %w[draw gust], report.role_rows.map(&:slug), "role rows come back in position order"
    assert_equal 8, draw_row.copies, "4 Boss's Orders and 4 Honedge"
    assert_equal 4, gust_row.copies
    # Four of the eight draw copies are Basic Pokémon, which the role bucket has to carry through —
    # counting all eight as non-Basic moves this number and nothing else on the page.
    assert_equal Decks::Odds::Report.percent(
      reference_deal.accessible(copies: 8, non_basic_copies: 4, seen: 0)
    ), draw_row.opening
    assert_equal 52, report.uncurated_copies, "60 cards, less the 8 that carry a role"
  end

  # The refusals. A report is still returned — the page needs the deck size to say what is wrong —
  # but it carries no rows, and nothing ever calls a Deal method that would raise.
  test "a deck with no Basic Pokemon refuses rather than answering" do
    @deck.deck_cards.create!(card: cards(:bosss_orders_meg), quantity: 60)

    report = Decks::Odds::Report.call(@deck.reload)

    assert_not report.playable?
    assert_equal 60, report.deck_size
    assert_equal 0, report.basics
    assert_empty report.card_rows
    assert_empty report.role_rows
    assert_empty report.prize_rows
  end

  test "a deck too small to deal a hand refuses rather than answering" do
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 3)

    report = Decks::Odds::Report.call(@deck.reload)

    assert_not report.playable?
    assert_empty report.card_rows
  end

  # Between a hand and a hand plus six prizes there is a deal and no prize block, which is the state
  # of a deck somebody is halfway through typing.
  test "a deck too small for prizes still answers, without a prize section" do
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 4)
    @deck.deck_cards.create!(card: cards(:bosss_orders_meg), quantity: 6)

    report = Decks::Odds::Report.call(@deck.reload)

    assert report.playable?
    assert_not report.prizes?
    assert_not report.reference_size?
    assert_equal 0, report.prize_count
    assert_equal 3, report.max_seen
    assert_equal 4, report.card_rows.find { |row| row.name == "Honedge" }.accessible_curve.size
    assert_empty report.prize_rows
  end

  # The lower boundary of the prize block, exactly: thirteen cards are a hand plus six prizes and
  # nothing else. A deck of ten and a deck of fourteen both behave the way the rule intends whether
  # the comparison is `>=` or `>`; only this size can tell the two apart.
  test "thirteen cards is the smallest deck that deals prizes" do
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 4)
    @deck.deck_cards.create!(card: cards(:bosss_orders_meg), quantity: 9)

    report = Decks::Odds::Report.call(@deck.reload)

    assert_equal 13, report.deck_size
    assert report.playable?
    assert report.prizes?
    assert_equal 6, report.prize_count
    assert_equal 6, report.max_seen, "thirteen cards, less the hand"
    assert_equal 0, report.max_draws, "every card outside the hand is a prize"
    assert_equal 7, report.card_rows.find { |row| row.name == "Honedge" }.all_prized_curve.size
    assert_not_empty report.prize_rows
  end

  # …and the lower boundary of the page itself. Seven cards are a hand and no draw pile: every curve
  # is one point long, there is no first turn to take, and `default_seen` clamps onto it. A deck of
  # three refuses whichever way the comparison is spelled; this one refuses only if it is wrong.
  test "seven cards is the smallest deck that answers at all" do
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 4)
    @deck.deck_cards.create!(card: cards(:bosss_orders_meg), quantity: 3)

    report = Decks::Odds::Report.call(@deck.reload)

    assert_equal 7, report.deck_size
    assert report.playable?
    assert_not report.prizes?
    assert_equal 0, report.max_seen, "a hand and no draw pile"
    assert_equal 0, report.default_seen, "there is no first turn to take"

    row = report.card_rows.find { |r| r.name == "Honedge" }

    assert_equal 1, row.accessible_curve.size
    assert_equal row.opening, row.accessible_curve.first
    assert_equal 100.0, row.opening, "four Basics in a seven-card deck, given a keepable hand"
  end
end
