require "test_helper"

# The card page promises "the same figures as the archetype's analysis". That promise is only as
# good as a comparison against the analysis's own services, so the central test walks every node
# this service returns and recomputes it through Archetypes::MetagameScope and
# Archetypes::CardStats with the very parameters the node links to. Hand-written expected numbers
# alone would agree with whatever rule the service happened to implement.
#
# Parity cannot see everything, and the tests after it exist for what it misses: the analysis
# gives the same sample whether or not a tournament link also names its pool or its venue, it says
# 0 % for an archetype the tree should never have listed, and it knows nothing about ordering. A
# plan-adversary pass mutated the service against the parity test alone and each of those
# mutations stayed green; each test below names the one it closes.
#
# The sample is built per test. No fixture is added: they are global, and the standings the suite
# already carries are counted elsewhere.
class Cards::ArchetypeUsageTest < ActiveSupport::TestCase
  test "every node reproduces the analysis page's figure for the parameters it links to" do
    sample = parity_sample

    nodes = %w[all paper online].sum { |venue| walk_parity(sample[:card], venue) }

    # The exact count, not a floor: a floor was satisfied by the archetype and tournament nodes
    # alone while every pool node was silently skipped.
    assert_equal 22, nodes
  end

  # A Trainer's fingerprint is the hash of its name, so a sample of Trainers cannot tell "same
  # fingerprint" from "same name". Two Pokémon of one name with different HP are two cards; the
  # same Pokémon printed in another set is the same card, and its list counts — "in any printing",
  # as the page says. Both halves, because a key on the card id alone passes the first.
  test "the card is its fingerprint, not its name" do
    played = pokemon("Usage Hoothoot", hp: 70)
    namesake = pokemon("Usage Hoothoot", hp: 80)
    reprint = Card.create!(name: "Usage Hoothoot", card_type: "Pokémon", set_name: "UZR",
                           set_number: "77", rarity: "Common", hp: 70, type_symbol: "Grass",
                           retreat_cost: 1, stage: "Basic")
    refute_equal played.fingerprint, namesake.fingerprint
    assert_equal played.fingerprint, reprint.fingerprint
    archetype = archetype_of_its_own
    event = standard_event(pool: standard_pools(:twm_por), date: Date.new(2026, 6, 1))
    record(event, archetype, deck: field_list(played => 2))
    record(event, archetype, deck: field_list(namesake => 3))
    record(event, archetype, deck: field_list(reprint => 4))

    usage = Cards::ArchetypeUsage.call(card: played).archetypes.sole.usage

    assert_equal [ 3, 2, 66.7, 2, 4 ],
      [ usage.lists_count, usage.playing_count, usage.pct, usage.min_copies, usage.max_copies ]
    assert_equal 3, walk_parity(played, "all"), "archetype, pool and tournament nodes, compared"
  end

  # `CardStats::GROUPING_KEY` keys a card with no fingerprint as 'card:<id>', alone. Matching such
  # a card by name, or by a NULL fingerprint, would fold its unfingerprinted namesake in.
  test "a card with no fingerprint counts its own printing only" do
    played = trainer("Usage Unprinted")
    namesake = trainer("Usage Unprinted")
    played.update_column(:fingerprint, nil)
    namesake.update_column(:fingerprint, nil)
    archetype = archetype_of_its_own
    event = standard_event(pool: standard_pools(:twm_por), date: Date.new(2026, 6, 1))
    record(event, archetype, deck: field_list(played => 1))
    record(event, archetype, deck: field_list(namesake => 4))
    record(event, archetype, deck: field_list(trainer("Usage Other") => 1))

    usage = Cards::ArchetypeUsage.call(card: played.reload).archetypes.sole.usage

    assert_equal [ 3, 1, 1, 1 ], [ usage.lists_count, usage.playing_count, usage.min_copies, usage.max_copies ]
    assert_equal 3, walk_parity(played, "all"), "archetype, pool and tournament nodes, compared"
  end

  # Two standings may point at one deck (`index_tournament_standings_on_deck_id` is not unique).
  # CardStats counts the deck once; counting standing rows would count it twice, in the
  # denominator and in the numerator.
  test "a deck recorded at two events counts once where both are in the sample" do
    card = trainer("Usage Twice")
    archetype = archetype_of_its_own
    pool = standard_pools(:twm_por)
    first_event = standard_event(pool: pool, date: Date.new(2026, 6, 1))
    second_event = standard_event(pool: pool, date: Date.new(2026, 6, 8))
    deck = field_list(card => 2)
    record(first_event, archetype, deck: deck)
    record(second_event, archetype, deck: deck)
    record(first_event, archetype, deck: field_list(trainer("Usage Filler") => 1))

    node = Cards::ArchetypeUsage.call(card: card).archetypes.sole

    assert_equal [ 2, 1, [ 2 ] ], [ node.usage.lists_count, node.usage.playing_count, node.usage.modes ]
    assert_equal [ 2, 1 ], [ node.pools.sole.usage.lists_count, node.pools.sole.usage.playing_count ]
    assert_equal 4, walk_parity(card, "all")
  end

  # A field list belongs to its standing's archetype, never to `decks.archetype_id`, which the
  # detector wrote at import and which contradicts the standing on 405 of 1223 field lists.
  test "a field list counts under its standing's archetype, not its deck's" do
    card = trainer("Usage Misfiled")
    standing_side = archetype_of_its_own
    deck_side = archetype_of_its_own
    event = standard_event(pool: standard_pools(:twm_por), date: Date.new(2026, 6, 1))
    deck = field_list(card => 1)
    deck.update!(archetype: deck_side)
    record(event, standing_side, deck: deck)

    assert_equal [ standing_side ], Cards::ArchetypeUsage.call(card: card).archetypes.map(&:archetype)
  end

  # Parity cannot see these: a tournament selects the same sample whether or not the link also
  # names its pool and venue, so only the exact Hash says the link is the one the page means.
  test "each node links with exactly the analysis parameters it reproduces" do
    sample = parity_sample
    pool = sample[:new_pool]

    paper = Cards::ArchetypeUsage.call(card: sample[:card], venue_param: "paper")
    node = paper.archetypes.find { |candidate| candidate.archetype == sample[:first] }
    assert_equal({ pool: "all", venue: "paper" }, node.analysis_params)
    pool_node = node.pools.find { |candidate| candidate.pool_id == pool.id }
    assert_equal({ pool: pool.id.to_s, venue: "paper" }, pool_node.analysis_params)
    assert_equal({ pool: pool.id.to_s, tournament: sample[:paper_new].id.to_s, venue: "paper" },
                 pool_node.tournaments.sole.analysis_params)

    all = Cards::ArchetypeUsage.call(card: sample[:card])
    node = all.archetypes.find { |candidate| candidate.archetype == sample[:first] }
    assert_equal({ pool: "all" }, node.analysis_params)
    outside = node.pools.last
    assert_nil outside.pool_id
    assert_equal "Other formats", outside.label
    assert_nil outside.analysis_params
    assert_equal({ pool: "all", tournament: sample[:glc].id.to_s }, outside.tournaments.sole.analysis_params)
    node.pools.each do |candidate|
      assert_equal candidate.pool_id.nil?, candidate.analysis_params.nil?, candidate.label
    end
  end

  # The pool order is most recent listed event first and "Other formats" last, whatever its
  # date — the GLC event here sits between the two pools' dates.
  test "pools are ordered by their latest listed event, the non-Standard node last" do
    sample = parity_sample
    node = Cards::ArchetypeUsage.call(card: sample[:card]).archetypes.find do |candidate|
      candidate.archetype == sample[:first]
    end

    assert_equal [ sample[:new_pool].id, sample[:old_pool].id, nil ], node.pools.map(&:pool_id)
  end

  # By each pool's *latest* event, not its earliest: here the pool holding the 30 June event comes
  # first although the other pool's only event (15 June) is later than its first one. And two pools
  # whose latest events share a date fall to the pool id, highest first, so the order cannot change
  # between two loads.
  test "pools order by their latest event, then by pool id" do
    card = trainer("Usage Interleaved")
    early, late = [ standard_pools(:twm_asc), standard_pools(:twm_por) ].sort_by(&:id)
    archetype = archetype_of_its_own
    record(standard_event(pool: early, date: Date.new(2026, 6, 1)), archetype, deck: field_list(card => 1))
    record(standard_event(pool: early, date: Date.new(2026, 6, 30)), archetype, deck: field_list(card => 1))
    record(standard_event(pool: late, date: Date.new(2026, 6, 15)), archetype, deck: field_list(card => 1))

    # Recorded higher id first, so the rows reach the sort in the order a missing tiebreak would
    # reverse into the wrong answer — recorded the other way round, insertion order alone passes.
    tied = archetype_of_its_own
    record(standard_event(pool: late, date: Date.new(2026, 7, 1)), tied, deck: field_list(card => 1))
    record(standard_event(pool: early, date: Date.new(2026, 7, 1)), tied, deck: field_list(card => 1))

    nodes = Cards::ArchetypeUsage.call(card: card).archetypes.index_by(&:archetype)

    assert_equal [ early.id, late.id ], nodes[archetype].pools.map(&:pool_id)
    assert_equal [ late.id, early.id ], nodes[tied].pools.map(&:pool_id)
  end

  # Played events only, newest first; the event where the archetype has a list and the card is
  # not played is a count, not a 0 % leaf.
  test "tournament leaves are the played events, the others a count" do
    sample = parity_sample
    node = Cards::ArchetypeUsage.call(card: sample[:card]).archetypes.find do |candidate|
      candidate.archetype == sample[:first]
    end
    pool_node = node.pools.find { |candidate| candidate.pool_id == sample[:new_pool].id }

    assert_equal [ sample[:online_new].id, sample[:paper_new].id ], pool_node.tournaments.map(&:tournament_id)
    assert_equal 1, pool_node.unplayed_tournaments_count
    assert_equal "#{sample[:paper_new].name} (#{I18n.l(sample[:paper_new].date)})",
                 pool_node.tournaments.last.label
  end

  # A pool where the archetype has lists and the card none is a node at 0 %, because a card
  # dropped after a rotation is an answer.
  test "a pool the card is absent from is listed at zero" do
    card = trainer("Usage Rotated")
    archetype = archetype_of_its_own
    record(standard_event(pool: standard_pools(:twm_asc), date: Date.new(2026, 3, 1)), archetype,
           deck: field_list(card => 2))
    record(standard_event(pool: standard_pools(:twm_por), date: Date.new(2026, 6, 1)), archetype,
           deck: field_list(trainer("Usage Successor") => 2))

    pools = Cards::ArchetypeUsage.call(card: card).archetypes.sole.pools

    assert_equal [ standard_pools(:twm_por).id, standard_pools(:twm_asc).id ], pools.map(&:pool_id)
    newest = pools.first
    assert_equal [ 1, 0, 0.0, nil, nil, [] ],
      [ newest.usage.lists_count, newest.usage.playing_count, newest.usage.pct,
        newest.usage.min_copies, newest.usage.max_copies, newest.usage.modes ]
    refute_predicate newest.usage, :played?
    assert_empty newest.tournaments
    assert_equal 1, newest.unplayed_tournaments_count
  end

  # By the number of lists playing it, not by percentage: 2 of 10 outranks 1 of 1. A tie on the
  # count falls to the name.
  test "archetypes are ordered by lists playing the card, then by name" do
    card = trainer("Usage Ranked")
    event = standard_event(pool: standard_pools(:twm_por), date: Date.new(2026, 6, 1))
    wide = Archetype.create!(primary_card: trainer("Usage Mmm Wide"))
    narrow = Archetype.create!(primary_card: trainer("Usage Zzz Narrow"))
    tied = Archetype.create!(primary_card: trainer("Usage Aaa Tied"))
    2.times { record(event, wide, deck: field_list(card => 1)) }
    8.times { record(event, wide, deck: field_list(trainer("Usage Pad #{next_index}") => 1)) }
    record(event, narrow, deck: field_list(card => 1))
    record(event, tied, deck: field_list(card => 1))
    record(event, tied, deck: field_list(trainer("Usage Pad #{next_index}") => 1))

    assert_equal [ wide, tied, narrow ], Cards::ArchetypeUsage.call(card: card).archetypes.map(&:archetype)
  end

  # Under a venue, an archetype is listed only if a list *in that venue* plays the card — the
  # analysis would agree with 0 % for any other, which is why parity cannot catch the leak.
  test "a venue lists only the archetypes playing the card in it" do
    sample = parity_sample

    online = Cards::ArchetypeUsage.call(card: sample[:card], venue_param: "online")

    assert_equal [ sample[:first] ], online.archetypes.map(&:archetype)
  end

  # Counted as lists *playing the card*, not lists: online holds three lists here and one of them
  # plays it.
  test "venue options count the lists playing the card under each venue" do
    sample = parity_sample

    result = Cards::ArchetypeUsage.call(card: sample[:card])

    assert_equal %w[all paper online], result.venue_options.map(&:value)
    assert_equal [ "All — 5 lists with this card", "Paper — 4 lists with this card",
                   "Online — 1 list with this card" ], result.venue_options.map(&:label)
    assert_predicate result, :venue_selectable?
    assert_equal :all, result.venue
  end

  # The archetype has an online list, but none that plays the card: Online is not a choice, and
  # asking for it clamps to All — with no `venue:` left in any link.
  test "a venue in which no list plays the card clamps to all and is not selectable" do
    card = trainer("Usage Paper Only")
    archetype = archetype_of_its_own
    pool = standard_pools(:twm_por)
    record(standard_event(pool: pool, date: Date.new(2026, 6, 1)), archetype, deck: field_list(card => 1))
    record(online_event(pool: pool, date: Date.new(2026, 6, 2)), archetype,
           deck: field_list(trainer("Usage Online Filler") => 1))

    result = Cards::ArchetypeUsage.call(card: card, venue_param: "online")

    assert_equal :all, result.venue
    refute_predicate result, :venue_selectable?
    links = result.archetypes.flat_map do |node|
      [ node.analysis_params ] + node.pools.map(&:analysis_params) +
        node.pools.flat_map(&:tournaments).map(&:analysis_params)
    end
    assert links.compact.none? { |params| params.key?(:venue) }, links.inspect
  end

  test "a malformed venue falls back to all without raising" do
    card = trainer("Usage Junk")
    [ [ "online" ], { "x" => "y" }, "nope", nil ].each do |junk|
      assert_equal :all, Cards::ArchetypeUsage.call(card: card, venue_param: junk).venue
    end
  end

  test "a card no list plays has nothing to report" do
    result = Cards::ArchetypeUsage.call(card: trainer("Usage Unplayed"))

    refute_predicate result, :any?
    refute_predicate result, :venue_selectable?
  end

  # Five statements once a list plays the card in a Standard pool: the rows, the archetypes, the pools and the two bounds
  # `StandardPool#name` reads. Measured outside the query cache, on a one-pool card and on one
  # spanning three archetypes, both pools and a non-Standard event — the shape an N+1 per
  # archetype or per pool would separate.
  test "the cost is flat in archetypes, pools and events" do
    small = trainer("Usage Small")
    record(standard_event(pool: standard_pools(:twm_por), date: Date.new(2026, 6, 1)),
           archetype_of_its_own, deck: field_list(small => 1))
    large = trainer("Usage Large")
    3.times do |index|
      archetype = archetype_of_its_own
      record(standard_event(pool: standard_pools(:twm_por), date: Date.new(2026, 6, 1 + index)), archetype,
             deck: field_list(large => 1))
      record(standard_event(pool: standard_pools(:twm_asc), date: Date.new(2026, 3, 1 + index)), archetype,
             deck: field_list(large => 2))
      record(unpooled_event(date: Date.new(2026, 4, 1 + index)), archetype, deck: field_list(large => 3))
    end

    costs = [ small, large ].map do |card|
      ActiveRecord::Base.uncached { count_queries { Cards::ArchetypeUsage.call(card: card) } }
    end

    assert_equal [ 5, 5 ], costs
  end

  private

  SET_NAME = "CAU".freeze

  # Two archetypes, two pools, a non-Standard event, both venues, a reprint, a list-less standing
  # and a list playing two printings of the card at once.
  def parity_sample
    card = trainer("Parity Gust")
    reprint = Card.create!(name: "Parity Gust", card_type: "Trainer", set_name: "UZR",
                           set_number: "9", rarity: "Uncommon", subtype: "Item")
    assert_equal card.fingerprint, reprint.fingerprint, "the reprint must share the fingerprint"
    filler = trainer("Parity Filler")

    first = archetype_of_its_own
    second = archetype_of_its_own
    old_pool = standard_pools(:twm_asc)
    new_pool = standard_pools(:twm_por)

    paper_old = standard_event(pool: old_pool, date: Date.new(2026, 3, 1))
    paper_new = standard_event(pool: new_pool, date: Date.new(2026, 6, 1))
    paper_new_other = standard_event(pool: new_pool, date: Date.new(2026, 6, 8))
    online_new = online_event(pool: new_pool, date: Date.new(2026, 6, 2))
    glc = unpooled_event(date: Date.new(2026, 4, 1))

    record(paper_old, first, deck: field_list(card => 2, filler => 4))
    record(paper_old, first, deck: field_list(filler => 4))
    record(paper_new, first, deck: field_list(card => 1, reprint => 1))
    record(paper_new, first, deck: field_list(filler => 3))
    record(paper_new, first)
    record(paper_new_other, first, deck: field_list(filler => 1))
    record(online_new, first, deck: field_list(reprint => 3))
    record(online_new, first, deck: field_list(filler => 2))
    record(glc, first, deck: field_list(card => 4))
    record(paper_new, second, deck: field_list(card => 1))
    record(online_new, second, deck: field_list(filler => 1))

    { card: card, first: first, second: second, old_pool: old_pool, new_pool: new_pool,
      paper_new: paper_new, online_new: online_new, glc: glc }
  end

  # Every linked node of one venue, compared. Returns how many it compared.
  def walk_parity(card, venue)
    result = Cards::ArchetypeUsage.call(card: card, venue_param: venue)
    result.archetypes.sum do |archetype_node|
      archetype = archetype_node.archetype
      assert_parity(card, archetype, archetype_node) +
        archetype_node.pools.sum do |pool_node|
          (pool_node.analysis_params ? assert_parity(card, archetype, pool_node) : 0) +
            pool_node.tournaments.sum { |tournament_node| assert_parity(card, archetype, tournament_node) }
        end
    end
  end

  # Returns 1 so the caller can count the comparisons it actually made. The key is
  # CardStats::GROUPING_KEY's: the fingerprint, or 'card:<id>' for a card that has none.
  def assert_parity(card, archetype, node)
    params = node.analysis_params
    scope = Archetypes::MetagameScope.call(
      archetype: archetype, pool_param: params[:pool], venue_param: params[:venue],
      tournament_param: params[:tournament]
    )
    stats = Archetypes::CardStats.call(standings: scope.listed_standings)
    key = card.fingerprint || "card:#{card.id}"
    entry = stats.categories.flat_map(&:name_groups).flat_map(&:entries)
                 .find { |candidate| candidate.fingerprint == key }

    label = "#{archetype.name} #{params.inspect}"
    assert_equal stats.lists_count, node.usage.lists_count, "lists for #{label}"
    if entry
      assert_equal [ entry.inclusion_count, entry.inclusion_pct, entry.min_copies, entry.max_copies, entry.modes ],
        [ node.usage.playing_count, node.usage.pct, node.usage.min_copies, node.usage.max_copies, node.usage.modes ],
        "usage for #{label}"
    else
      assert_equal [ 0, 0.0 ], [ node.usage.playing_count, node.usage.pct ], "usage for #{label}"
    end
    1
  end

  def archetype_of_its_own
    Archetype.create!(primary_card: trainer("Usage Marker #{next_index}"))
  end

  def trainer(name, subtype: "Item")
    Card.create!(name: name, card_type: "Trainer", set_name: SET_NAME,
                 set_number: next_index.to_s, rarity: "Uncommon", subtype: subtype)
  end

  def pokemon(name, hp:)
    Card.create!(name: name, card_type: "Pokémon", set_name: SET_NAME,
                 set_number: next_index.to_s, rarity: "Common", hp: hp,
                 type_symbol: "Grass", retreat_cost: 1, stage: "Basic")
  end

  def standard_event(pool:, date:)
    Tournament.create!(name: "Usage Event #{next_index}", date: date, format: "standard",
                       standard_pool: pool, tier: "regional", created_by: users(:one))
  end

  def online_event(pool:, date:)
    Tournament.create!(name: "Usage Online #{next_index}", date: date, format: "standard",
                       standard_pool: pool, tier: "other", online: true, created_by: users(:one))
  end

  def unpooled_event(date:)
    Tournament.create!(name: "Usage GLC #{next_index}", date: date, format: "glc",
                       tier: "league_cup", created_by: users(:one))
  end

  def record(event, archetype, deck: nil)
    TournamentStanding.create!(tournament: event, archetype: archetype, deck: deck,
                               player_name: "Player #{next_index}",
                               division: event.online? ? "open" : "masters",
                               created_by: users(:one))
  end

  def field_list(copies_by_card)
    Deck.create!(name: "Field list #{next_index}", user: nil, shared: true, physical: false,
                 format: "glc").tap do |deck|
      copies_by_card.each { |card, copies| deck.deck_cards.create!(card: card, quantity: copies) }
    end
  end

  def next_index
    @next_index = @next_index.to_i + 1
  end
end
