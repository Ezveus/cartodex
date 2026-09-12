require "test_helper"

# The combination calculator's model, and the app's only service whose whole input is a string a
# reader can type into the address bar. Every malformed shape fails closed into a sentence — never
# into a number computed from a misread request.
class Decks::Odds::ComboTest < ActiveSupport::TestCase
  setup do
    @deck = decks(:one)
    @deck.deck_cards.destroy_all
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 4)              # Basic
    @deck.deck_cards.create!(card: cards(:teal_mask_ogerpon_ex), quantity: 3) # Basic
    @deck.deck_cards.create!(card: cards(:bosss_orders_meg), quantity: 4)     # Trainer, fingerprinted
    @deck.deck_cards.create!(card: cards(:trainer_card), quantity: 2)         # Trainer, NO fingerprint
    @deck.deck_cards.create!(card: cards(:basic_psychic_energy), quantity: 47)
    @report = Decks::Odds::Report.call(@deck.reload)
  end

  def combo(param) = Decks::Odds::Combo.call(report: @report, param: param)

  # The key the page puts in the param: a fingerprint, or the "card:<id>" fallback for a printing
  # that has none. Both shapes have to survive a round trip through the URL.
  def key(name) = Decks::Odds::Groups.key_for(cards(name))

  def deal = Decks::Odds::Deal.new(deck_size: 60, basics: 7)

  test "two buckets are answered by inclusion-exclusion over the deck's own groups" do
    result = combo("#{key(:honedge)}|#{key(:bosss_orders_meg)}")

    assert result.answered?
    assert_nil result.error
    assert_equal [ [ "Honedge" ], [ "Boss's Orders" ] ],
      result.buckets.map { |bucket| bucket.map(&:name) }

    assert_equal 54, result.curve.size
    assert_equal Decks::Odds::Report.percent(deal.all_buckets(buckets: [ [ 4, 0 ], [ 4, 4 ] ], seen: 0)),
      result.curve.first
    assert_equal Decks::Odds::Report.percent(deal.all_buckets(buckets: [ [ 4, 0 ], [ 4, 4 ] ], seen: 10)),
      result.curve[10]
  end

  # A bucket is an OR: its sizes add, which is only sound because the buckets are disjoint.
  test "a bucket holding two cards adds their copies" do
    result = combo("#{key(:honedge)}.#{key(:teal_mask_ogerpon_ex)}|#{key(:bosss_orders_meg)}")

    assert result.answered?
    assert_equal Decks::Odds::Report.percent(deal.all_buckets(buckets: [ [ 7, 0 ], [ 4, 4 ] ], seen: 0)),
      result.curve.first
  end

  # Four is the largest shape the calculator accepts, and it is the *accepted* edge of MAX_BUCKETS —
  # the prescribed five-bucket refusal below pins the rejected edge, and on its own `>=` for `>`
  # satisfies both. It is also the only place in the suite where Deal#all_buckets expands all
  # sixteen inclusion-exclusion terms, so the curve is checked against Deal rather than merely
  # produced.
  test "four buckets are answered, and by the same sixteen-term expansion Deal computes" do
    result = combo([ key(:honedge), key(:teal_mask_ogerpon_ex),
                     key(:bosss_orders_meg), key(:trainer_card) ].join("|"))

    assert result.answered?
    assert_nil result.error
    assert_equal [ [ "Honedge" ], [ "Teal Mask Ogerpon ex" ], [ "Boss's Orders" ], [ "Boss's Orders" ] ],
      result.buckets.map { |bucket| bucket.map(&:name) }

    assert_equal Decks::Odds::Report.percent(
      deal.all_buckets(buckets: [ [ 4, 0 ], [ 3, 0 ], [ 4, 4 ], [ 2, 2 ] ], seen: 0)
    ), result.curve.first
  end

  # A card with no fingerprint groups under "card:<id>", which contains a colon — a character the
  # two separators must not collide with.
  test "a group with no fingerprint can still be named" do
    result = combo("#{key(:trainer_card)}|#{key(:honedge)}")

    assert result.answered?
    assert_equal [ [ "Boss's Orders" ], [ "Honedge" ] ],
      result.buckets.map { |bucket| bucket.map(&:name) }
    assert_equal Decks::Odds::Report.percent(deal.all_buckets(buckets: [ [ 2, 2 ], [ 4, 0 ] ], seen: 0)),
      result.curve.first
  end

  test "no combination asked is not an error" do
    [ nil, "", "   " ].each do |param|
      result = combo(param)

      assert_not result.asked?, param.inspect
      assert_not result.answered?, param.inspect
      assert_nil result.error, param.inspect
      assert_empty result.buckets, param.inspect
    end
  end

  # The picker greys a used card out, but the picker is not a guarantee — the param is a URL, and
  # disjointness is what lets Deal add bucket sizes rather than compute a set union. A param that
  # broke it would not raise; it would return a wrong number.
  test "a card in two buckets fails closed" do
    result = combo("#{key(:honedge)}|#{key(:honedge)}")

    assert result.asked?
    assert_not result.answered?
    assert_nil result.curve
    assert_equal "A card can only be in one group.", result.error
  end

  test "a card this deck does not play fails closed" do
    result = combo("#{key(:honedge)}|#{key(:budew_pre)}")

    assert_not result.answered?
    assert_equal "That combination names a card this deck does not play.", result.error
  end

  test "more than four buckets fails closed" do
    result = combo(%w[a b c d e].map { |suffix| "#{key(:honedge)}#{suffix}" }.join("|"))

    assert_not result.answered?
    assert_equal "Pick at most 4 groups of cards.", result.error
  end

  test "an empty bucket fails closed" do
    [ "#{key(:honedge)}||#{key(:bosss_orders_meg)}",
      "|#{key(:honedge)}",
      "#{key(:honedge)}|" ].each do |param|
      result = combo(param)

      assert_not result.answered?, param
      assert_equal "Every group must hold at least one card.", result.error, param
    end
  end

  # PubliclyReachable rescues RecordNotFound and NotAuthorizedError and nothing else, so a
  # NoMethodError here would be an unhandled 500 for any bot that tries `?combo[a]=b` — the same
  # trap DecksController#shared documents on its `page` param.
  test "a param that is not a string fails closed rather than raising" do
    [ { "a" => "b" }, [ "a", "b" ], 42, ActionController::Parameters.new(a: "b") ].each do |param|
      result = combo(param)

      assert_not result.answered?, param.inspect
      assert result.error.present?, param.inspect
    end
  end

  # The calculator answers "I have seen one of each", so it must reach certainty at the same point
  # every other curve on the page does.
  test "a combination is certain once every card outside the hand has been seen" do
    result = combo("#{key(:honedge)}|#{key(:bosss_orders_meg)}")

    assert_equal 100.0, result.curve.last
  end

  # A deck that cannot start a game has no conditional probability to offer, and Combo must not be
  # the thing that discovers it by raising.
  test "an unplayable deck answers nothing" do
    @deck.deck_cards.destroy_all
    @deck.deck_cards.create!(card: cards(:bosss_orders_meg), quantity: 60)
    report = Decks::Odds::Report.call(@deck.reload)

    result = Decks::Odds::Combo.call(report: report, param: key(:bosss_orders_meg))

    assert_not result.answered?
    assert_equal "This deck cannot start a game, so there is nothing to compute.", result.error
  end
end
