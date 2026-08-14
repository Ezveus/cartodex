require "test_helper"

class Search::GlobalTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @deck = decks(:one)
    @deck.update!(user: @user, name: "Ogerpon Toolbox")
  end

  test "returns a blank result for a query shorter than the minimum" do
    [ "", "   ", "o" ].each do |query|
      result = Search::Global.call(user: @user, query: query)

      assert_predicate result, :blank?, "#{query.inspect} must not search"
      assert_empty result.decks
      assert_empty result.cards
      assert_empty result.tournaments
      assert_equal 0, result.deck_total
    end
  end

  test "issues zero SQL queries for a query shorter than the minimum" do
    query_count = 0
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_, _, _, _, payload|
      query_count += 1 unless payload[:name].in?(%w[SCHEMA TRANSACTION])
    end

    begin
      Search::Global.call(user: @user, query: "o")
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    assert_equal 0, query_count, "a query below MIN_QUERY_LENGTH must not touch the database"
  end

  test "groups matches by type" do
    result = Search::Global.call(user: @user, query: "ogerpon")

    assert_not_predicate result, :blank?
    assert_predicate result, :any?
    assert_includes result.decks, @deck
    assert_includes result.cards, cards(:teal_mask_ogerpon_ex)
    assert_empty result.tournaments
  end

  test "reports no matches for a query that hits nothing" do
    result = Search::Global.call(user: @user, query: "zzzznothing")

    assert_not_predicate result, :blank?
    assert_not_predicate result, :any?
  end

  test "caps each group and still reports the full total" do
    7.times { |i| @user.decks.create!(name: "Ogerpon Build #{i}") }

    result = Search::Global.call(user: @user, query: "ogerpon", limit: 5)

    assert_equal 5, result.decks.size
    assert_equal 8, result.deck_total, "7 new decks plus the one from setup"
  end

  test "finds a deck through its archetype" do
    @deck.update!(name: "Tuesday List", archetype: archetypes(:ogerpon))

    result = Search::Global.call(user: @user, query: "ogerpon")

    assert_includes result.decks, @deck
  end

  test "excludes another user's decks and tournaments" do
    decks(:two).update!(user: users(:two), name: "Ogerpon Toolbox")
    users(:two).tournaments.create!(deck: decks(:two), name: "Ogerpon Open",
                                    date: Date.new(2026, 4, 1), format: "standard", tier: "league_cup")

    result = Search::Global.call(user: @user, query: "ogerpon")

    assert_not_includes result.decks, decks(:two)
    assert_empty result.tournaments
  end

  test "searches the whole card catalog, not just the user's collection" do
    card = cards(:teal_mask_ogerpon_ex)

    assert_empty @user.collections.where(card: card), "sanity: the user does not own this card"
    assert_includes Search::Global.call(user: @user, query: "ogerpon").cards, card
  end

  test "matches the user's own tournaments by name" do
    tournament = @user.tournaments.create!(deck: @deck, name: "Ogerpon Open",
                                           date: Date.new(2026, 4, 1), format: "standard", tier: "league_cup")

    result = Search::Global.call(user: @user, query: "ogerpon")

    assert_includes result.tournaments, tournament
    assert_equal 1, result.tournament_total
  end

  # A page that came back short of the cap is the whole result set, so its size is the total and
  # the COUNT — a second full LIKE scan of the card catalog — is skipped. Shrinking the cap to 1
  # fills every non-empty group, which is what makes the extra queries appear.
  test "skips the total count for a group the cap did not truncate" do
    @user.tournaments.create!(deck: @deck, name: "Ogerpon Open",
                              date: Date.new(2026, 4, 1), format: "standard", tier: "league_cup")

    unfilled = count_queries { Search::Global.call(user: @user, query: "ogerpon", limit: 5) }
    filled   = count_queries { Search::Global.call(user: @user, query: "ogerpon", limit: 1) }

    assert_operator unfilled, :<, filled,
      "a group that fits under the cap still paid for its COUNT: #{unfilled} vs #{filled}"
  end

  # The short-circuit above must not cost the truncated case its real total: "See all 5 decks"
  # when there are 8 is the bug it would introduce.
  test "still reports the real total when the cap truncated a group" do
    7.times { |i| @user.decks.create!(name: "Ogerpon Build #{i}") }

    result = Search::Global.call(user: @user, query: "ogerpon")

    assert_equal 5, result.decks.size
    assert_equal 8, result.deck_total
  end

  # Cards go through the same matcher as /cards?q=, so a set code and number narrow the query
  # there too and the "see all" count stays honest.
  test "narrows cards by set code and number like the cards page does" do
    card = cards(:teal_mask_ogerpon_ex)
    result = Search::Global.call(user: @user, query: "Ogerpon #{card.set_name} #{card.set_number}")

    assert_equal [ card ], result.cards
  end
end
