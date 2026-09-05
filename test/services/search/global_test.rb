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
    7.times { |i| @user.decks.create!(name: "Ogerpon Build #{i}", standard_pool: standard_pools(:twm_por)) }

    result = Search::Global.call(user: @user, query: "ogerpon", limit: 5)

    assert_equal 5, result.decks.size
    assert_equal 8, result.deck_total, "7 new decks plus the one from setup"
  end

  test "finds a deck through its archetype" do
    @deck.update!(name: "Tuesday List", archetype: archetypes(:ogerpon))

    result = Search::Global.call(user: @user, query: "ogerpon")

    assert_includes result.decks, @deck
  end

  test "excludes another user's decks" do
    decks(:two).update!(user: users(:two), name: "Ogerpon Toolbox")

    result = Search::Global.call(user: @user, query: "ogerpon")

    assert_not_includes result.decks, decks(:two)
  end

  # Inverted deliberately. Under the old model a tournament belonged to one member, so this
  # asserted an event another member recorded was invisible. The catalog is shared now: it is
  # the same event, and hiding it was the bug the split fixes.
  test "a member's search finds an event another member catalogued" do
    other = Tournament.create!(name: "Ogerpon Open", date: Date.new(2026, 4, 1),
                               tier: "league_cup", format: "expanded", created_by: users(:two))

    result = Search::Global.call(user: users(:one), query: "ogerpon")

    assert_includes result.tournaments, other
  end

  # A member's tournaments group becomes the whole catalog: an event another member catalogued
  # is the same event, and it used to be invisible because the scope was @user.tournaments.
  test "a member's search finds a fixture event catalogued by another member" do
    result = Search::Global.call(user: users(:one), query: "local league")

    assert_includes result.tournaments, tournaments(:two)
  end

  test "a visitor's search finds tournaments in the catalog" do
    result = Search::Global.call(user: nil, query: "regional")

    assert_includes result.tournaments, tournaments(:one)
    assert_equal 1, result.tournament_total
  end

  test "searches the whole card catalog, not just the user's collection" do
    card = cards(:teal_mask_ogerpon_ex)

    assert_empty @user.collections.where(card: card), "sanity: the user does not own this card"
    assert_includes Search::Global.call(user: @user, query: "ogerpon").cards, card
  end

  test "matches the user's own tournaments by name" do
    tournament = Tournament.create!(name: "Ogerpon Open",
                                    date: Date.new(2026, 4, 1), format: "standard",
                                    standard_pool: standard_pools(:twm_por), tier: "league_cup",
                                    created_by: @user)

    result = Search::Global.call(user: @user, query: "ogerpon")

    assert_includes result.tournaments, tournament
    assert_equal 1, result.tournament_total
  end

  # A page that came back short of the cap is the whole result set, so its size is the total and
  # the COUNT — a second full LIKE scan of the card catalog — is skipped. Shrinking the cap to 1
  # fills every non-empty group, which is what makes the extra queries appear.
  test "skips the total count for a group the cap did not truncate" do
    Tournament.create!(name: "Ogerpon Open",
                       date: Date.new(2026, 4, 1), format: "standard",
                       standard_pool: standard_pools(:twm_por), tier: "league_cup",
                       created_by: @user)

    unfilled = count_queries { Search::Global.call(user: @user, query: "ogerpon", limit: 5) }
    filled   = count_queries { Search::Global.call(user: @user, query: "ogerpon", limit: 1) }

    assert_operator unfilled, :<, filled,
      "a group that fits under the cap still paid for its COUNT: #{unfilled} vs #{filled}"
  end

  # The short-circuit above must not cost the truncated case its real total: "See all 5 decks"
  # when there are 8 is the bug it would introduce.
  test "still reports the real total when the cap truncated a group" do
    7.times { |i| @user.decks.create!(name: "Ogerpon Build #{i}", standard_pool: standard_pools(:twm_por)) }

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

  test "a visitor searches cards and shared decks, and nothing personal" do
    decks(:two).update!(user: users(:two), shared: true, name: "Zoroark Box")

    result = Search::Global.call(user: nil, query: "Zoroark")

    assert_empty result.decks
    assert_equal 0, result.deck_total
    assert_empty result.tournaments
    assert_equal [ "Zoroark Box" ], result.shared_decks.map(&:name)
  end

  test "a member's own shared deck appears once, in their own group" do
    mine = decks(:one)
    mine.update!(user: users(:one), shared: true, name: "Zoroark Box")

    result = Search::Global.call(user: users(:one), query: "Zoroark")

    assert_equal [ mine ], result.decks
    assert_empty result.shared_decks
    # Without where.not(user:) this is 2, and Search::ResultsList would emit the same DOM id
    # twice for it.
    assert_equal 1, result.deck_total + result.shared_deck_total
  end

  test "the shared group carries the preloads its rows need" do
    decks(:two).update!(user: users(:two), shared: true, name: "Zoroark Box")

    result = Search::Global.call(user: nil, query: "Zoroark")
    deck = result.shared_decks.first

    assert_predicate deck.association(:standard_pool), :loaded?
    assert_predicate deck.association(:archetype), :loaded?
  end

  # `where.not(user: @user)` compiles to `user_id != ?`, which SQL evaluates to NULL — not true —
  # for an ownerless row, so every field list vanished from a signed-in member's spotlight.
  test "an ownerless shared deck reaches a signed-in member's shared results" do
    decks(:field_list).update!(name: "Zoroark Field List", shared: true)

    result = Search::Global.call(user: users(:one), query: "Zoroark")

    assert_includes result.shared_decks.map(&:name), "Zoroark Field List"
  end

  test "a visitor sees an ownerless shared deck too" do
    decks(:field_list).update!(name: "Zoroark Field List", shared: true)

    result = Search::Global.call(user: nil, query: "Zoroark")

    assert_includes result.shared_decks.map(&:name), "Zoroark Field List"
  end

  # The fifth group. Archetype.search spans three columns — the archetype's own name and both
  # member cards' — so the two paths into it are tested apart: a custom-named archetype is the
  # only way to have a name that does *not* contain its lead card's, which is what makes
  # "found by name" and "found by card" distinguishable at all.
  test "a member finds an archetype by its own name" do
    archetype = Archetype.create!(primary_card: cards(:doublade), custom_name: true,
                                  name: "Metal Toolbox")

    result = Search::Global.call(user: @user, query: "metal toolbox")

    assert_equal [ archetype ], result.archetypes
    assert_equal 1, result.archetype_total
  end

  test "a member finds an archetype through a member card's name" do
    archetype = Archetype.create!(primary_card: cards(:doublade), custom_name: true,
                                  name: "Metal Toolbox")

    result = Search::Global.call(user: @user, query: "doublade")

    assert_includes result.archetypes, archetype,
      "the archetype's own name does not contain \"doublade\" — only its lead card's does"
  end

  test "the archetype group carries the preloads its rows need" do
    Archetype.create!(primary_card: cards(:doublade), custom_name: true, name: "Metal Toolbox")

    archetype = Search::Global.call(user: @user, query: "metal toolbox").archetypes.first

    # A row prints both member cards' printing_labels, which is two queries per archetype
    # without these.
    assert_predicate archetype.association(:primary_card), :loaded?
    assert_predicate archetype.association(:secondary_card), :loaded?
  end

  # /archetypes is inside the `authenticate :user` block, so an option here would be a link to a
  # sign-in wall. Deck.none is the pattern archetype_scope copies, and the point of it is that
  # nothing is *queried* either: the assertion below is on the SQL, not just on the result.
  #
  # The regex is deliberately narrow. Deck.search embeds `Archetype.search(q).select(:id)` as a
  # subquery, so the shared-deck query mentions the archetypes table for a visitor too and always
  # has — what must not appear is a query that selects archetype *rows*.
  test "a visitor gets no archetypes, and none are queried for" do
    Archetype.create!(primary_card: cards(:doublade), custom_name: true, name: "Metal Toolbox")

    sql = capture_queries { @result = Search::Global.call(user: nil, query: "metal toolbox") }

    # Asserted before the two below, so that a regression is reported as "the database was
    # touched" rather than as "the list was not empty" — the second is a consequence, and the
    # first is the claim.
    assert_empty sql.grep(/SELECT (DISTINCT )?"archetypes"\.\*/i),
      "a visitor's spotlight loaded archetype rows"
    assert_empty @result.archetypes
    assert_equal 0, @result.archetype_total
  end
end
