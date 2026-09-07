require "test_helper"

# The sample is built per test, never fixtured: fixtures are global, and the two standings the
# suite already carries on tournaments(:one) are counted by the standings sheet's pagination tests
# and by the tournament catalogue's. Everything here hangs off an archetype of its own, so nothing
# this file creates can be seen by a test that counts rows.
class Archetypes::MetagameScopeTest < ActiveSupport::TestCase
  test "options list every pool actually present, each labelled with its list count, plus All formats" do
    archetype = archetype_of_its_own
    old_event = standard_event(pool: standard_pools(:twm_asc), date: Date.new(2025, 6, 1))
    3.times { record(old_event, archetype, deck: field_list) }
    new_event = standard_event(pool: standard_pools(:twm_por), date: Date.new(2026, 5, 1))
    record(new_event, archetype, deck: field_list)

    result = Archetypes::MetagameScope.call(archetype: archetype)

    assert_equal [
      [ standard_pools(:twm_por).id.to_s, "#{standard_pools(:twm_por).name} — 1 list", 1 ],
      [ standard_pools(:twm_asc).id.to_s, "#{standard_pools(:twm_asc).name} — 3 lists", 3 ],
      [ Archetypes::MetagameScope::ALL, "All formats — 4 lists", 4 ]
    ], result.options.map { |option| [ option.value, option.label, option.lists_count ] }
    assert_predicate result, :selectable?
  end

  # The case that tells the two candidate defaults apart: the older pool holds three times the
  # lists of the newer one, which is the shape the production data has (68 lists in 2025 against 3
  # in 2026). Defaulting to the best-populated sample would answer "what does this deck play?"
  # with data from a rotation the heading never names.
  test "the default is the most recent pool, not the best-populated one" do
    archetype = archetype_of_its_own
    old_event = standard_event(pool: standard_pools(:twm_asc), date: Date.new(2025, 6, 1))
    3.times { record(old_event, archetype, deck: field_list) }
    new_event = standard_event(pool: standard_pools(:twm_por), date: Date.new(2026, 5, 1))
    record(new_event, archetype, deck: field_list)

    result = Archetypes::MetagameScope.call(archetype: archetype)

    assert_equal standard_pools(:twm_por), result.pool
    assert_equal 1, result.lists_count
    refute_predicate result, :all_formats?
  end

  test "ALL drops the pool filter and counts every recorded list" do
    archetype = archetype_of_its_own
    old_event = standard_event(pool: standard_pools(:twm_asc), date: Date.new(2025, 6, 1))
    3.times { record(old_event, archetype, deck: field_list) }
    new_event = standard_event(pool: standard_pools(:twm_por), date: Date.new(2026, 5, 1))
    record(new_event, archetype, deck: field_list)

    result = Archetypes::MetagameScope.call(archetype: archetype,
                                            pool_param: Archetypes::MetagameScope::ALL)

    assert_nil result.pool
    assert_predicate result, :all_formats?
    assert_equal 4, result.lists_count
    assert_equal 4, result.standings.count
  end

  # params[:pool] can be an Array or a Hash — the action is reachable by anyone with a session —
  # and neither responds to to_i. None of these may raise, and all of them land on the default.
  test "an unknown, blank or non-scalar pool parameter falls back to the default" do
    archetype = archetype_of_its_own
    event = standard_event(pool: standard_pools(:twm_por), date: Date.new(2026, 5, 1))
    record(event, archetype, deck: field_list)

    [ nil, "", "   ", "999999", "not-a-number", [ "1" ], { a: 1 } ].each do |param|
      result = Archetypes::MetagameScope.call(archetype: archetype, pool_param: param)

      assert_equal standard_pools(:twm_por), result.pool, "#{param.inspect} should fall back"
      assert_equal 1, result.lists_count
    end
  end

  test "standings holds every row of the pool while listed_standings holds only the ones with a list" do
    archetype = archetype_of_its_own
    event = standard_event(pool: standard_pools(:twm_por), date: Date.new(2026, 5, 1))
    listed = [ record(event, archetype, deck: field_list), record(event, archetype, deck: field_list) ]
    bare = record(event, archetype)

    result = Archetypes::MetagameScope.call(archetype: archetype)

    assert_equal 3, result.standings.count
    assert_equal 2, result.lists_count
    assert_equal ([ bare ] + listed).map(&:id).sort, result.standings.pluck(:id).sort
    assert_equal listed.map(&:id).sort, result.listed_standings.pluck(:id).sort
  end

  test "small_sample? flips either side of SMALL_SAMPLE" do
    archetype = archetype_of_its_own
    event = standard_event(pool: standard_pools(:twm_por), date: Date.new(2026, 5, 1))
    (Archetypes::MetagameScope::SMALL_SAMPLE - 1).times { record(event, archetype, deck: field_list) }

    below = Archetypes::MetagameScope.call(archetype: archetype)

    assert_equal Archetypes::MetagameScope::SMALL_SAMPLE - 1, below.lists_count
    assert_predicate below, :small_sample?

    record(event, archetype, deck: field_list)
    at_threshold = Archetypes::MetagameScope.call(archetype: archetype)

    assert_equal Archetypes::MetagameScope::SMALL_SAMPLE, at_threshold.lists_count
    refute_predicate at_threshold, :small_sample?
  end

  # Zero lists is not a small sample, it is no sample — the page has a different thing to say
  # about it, so the two predicates must not both fire.
  test "no lists at all is no_lists?, not small_sample?" do
    archetype = archetype_of_its_own
    event = standard_event(pool: standard_pools(:twm_por), date: Date.new(2026, 5, 1))
    record(event, archetype)

    result = Archetypes::MetagameScope.call(archetype: archetype)

    assert_equal 1, result.standings.count
    assert_predicate result, :no_lists?
    refute_predicate result, :small_sample?
  end

  test "selectable? is false when All formats is the only option" do
    archetype = archetype_of_its_own
    record(unpooled_event(date: Date.new(2026, 4, 1)), archetype, deck: field_list)

    result = Archetypes::MetagameScope.call(archetype: archetype)

    assert_equal [ Archetypes::MetagameScope::ALL ], result.options.map(&:value)
    # unpooled? on its own is true here and must not carry selectable? with it: there is exactly
    # one option, so the control the flag would render is a <select> of one.
    assert_predicate result, :unpooled?
    refute_predicate result, :selectable?
    assert_nil result.pool
    assert_predicate result, :all_formats?
  end

  # Two options, one sample. "TEF-PBL — 4 lists" and "All formats — 4 lists" are two labels for
  # the same four lists, and switching between them changes nothing on the page below. Measured
  # on the production data, most archetypes carrying any standing at all are in this shape.
  test "selectable? is false when every standing sits in the one pool" do
    archetype = archetype_of_its_own
    event = standard_event(pool: standard_pools(:twm_por), date: Date.new(2026, 5, 1))
    4.times { record(event, archetype, deck: field_list) }

    result = Archetypes::MetagameScope.call(archetype: archetype)

    assert_equal [ standard_pools(:twm_por).id.to_s, Archetypes::MetagameScope::ALL ],
      result.options.map(&:value)
    assert_equal [ 4, 4 ], result.options.map(&:lists_count)
    refute_predicate result, :unpooled?
    refute_predicate result, :selectable?
  end

  # The same two options, and now they name two different samples: the GLC list is counted under
  # "All formats" and under no pool option, so the choice is real even though there is one pool.
  test "selectable? is true when a pool and an event outside Standard both hold lists" do
    archetype = archetype_of_its_own
    pooled = standard_event(pool: standard_pools(:twm_por), date: Date.new(2026, 5, 1))
    record(pooled, archetype, deck: field_list)
    record(unpooled_event(date: Date.new(2026, 4, 1)), archetype, deck: field_list)

    result = Archetypes::MetagameScope.call(archetype: archetype)

    assert_equal [ standard_pools(:twm_por).id.to_s, Archetypes::MetagameScope::ALL ],
      result.options.map(&:value)
    assert_equal [ 1, 2 ], result.options.map(&:lists_count)
    assert_predicate result, :unpooled?
    assert_predicate result, :selectable?
  end

  # The notice under the selector promises that a fuller sample is one click away. That promise is
  # false on the sample that is already the largest, which is where the default lands whenever the
  # newest pool is also the best-populated one.
  test "fuller_sample_available? is false on the largest sample and true below it" do
    archetype = archetype_of_its_own
    old_event = standard_event(pool: standard_pools(:twm_asc), date: Date.new(2025, 6, 1))
    3.times { record(old_event, archetype, deck: field_list) }
    new_event = standard_event(pool: standard_pools(:twm_por), date: Date.new(2026, 5, 1))
    record(new_event, archetype, deck: field_list)

    default = Archetypes::MetagameScope.call(archetype: archetype)

    assert_equal 1, default.lists_count
    assert_predicate default, :fuller_sample_available?

    blended = Archetypes::MetagameScope.call(archetype: archetype,
                                             pool_param: Archetypes::MetagameScope::ALL)

    assert_equal 4, blended.lists_count
    refute_predicate blended, :fuller_sample_available?

    # Not merely "ALL is the largest option": the 3-list pool is fuller than the 1-list default
    # too, and is the one a reader would actually click.
    fuller = Archetypes::MetagameScope.call(archetype: archetype,
                                            pool_param: standard_pools(:twm_asc).id.to_s)

    assert_equal 3, fuller.lists_count
    assert_predicate fuller, :fuller_sample_available?
  end

  # A non-Standard event carries no pool by design, so it can only ever be counted under
  # "All formats" — and the newest event being one of them must not move the default.
  test "events outside Standard are counted only under All formats" do
    archetype = archetype_of_its_own
    pooled = standard_event(pool: standard_pools(:twm_por), date: Date.new(2026, 5, 1))
    record(pooled, archetype, deck: field_list)
    glc = unpooled_event(date: Date.new(2026, 6, 1))
    2.times { record(glc, archetype, deck: field_list) }

    result = Archetypes::MetagameScope.call(archetype: archetype)

    assert_equal [ standard_pools(:twm_por).id.to_s, Archetypes::MetagameScope::ALL ],
      result.options.map(&:value)
    assert_equal standard_pools(:twm_por), result.pool
    assert_equal 1, result.lists_count
    assert_equal 3, result.options.last.lists_count
  end

  # The blend the pool axis cannot see: an online weekly and a Regional anchored to the same pool
  # land in the same bucket, so "TEF-PBL — 4 lists" would be three weeklies and one Regional with
  # nothing on the page saying so. The count is per sample, not per archetype — switching pools
  # must move it.
  test "online_lists_count counts the lists in the sample that come from an online event" do
    archetype = archetype_of_its_own
    pool = standard_pools(:twm_por)
    paper = standard_event(pool: pool, date: Date.new(2026, 5, 1))
    record(paper, archetype, deck: field_list)
    3.times do |i|
      record(online_event(pool: pool, date: Date.new(2026, 5, 10) + i), archetype, deck: field_list)
    end

    result = Archetypes::MetagameScope.call(archetype: archetype)

    assert_equal pool, result.pool
    assert_equal 4, result.lists_count
    assert_equal 3, result.online_lists_count
    assert_predicate result, :online_lists?
  end

  # The figure has to follow the selector, or the sentence under it describes a sample the reader
  # is not looking at.
  test "online_lists_count is scoped to the selected pool, and All formats blends both" do
    archetype = archetype_of_its_own
    old_pool = standard_pools(:twm_asc)
    2.times do |i|
      record(standard_event(pool: old_pool, date: Date.new(2025, 6, 1) + i), archetype,
             deck: field_list)
    end
    new_pool = standard_pools(:twm_por)
    record(online_event(pool: new_pool, date: Date.new(2026, 5, 1)), archetype, deck: field_list)

    default = Archetypes::MetagameScope.call(archetype: archetype)

    assert_equal new_pool, default.pool
    assert_equal [ 1, 1 ], [ default.lists_count, default.online_lists_count ]

    older = Archetypes::MetagameScope.call(archetype: archetype, pool_param: old_pool.id.to_s)

    assert_equal [ 2, 0 ], [ older.lists_count, older.online_lists_count ]
    refute_predicate older, :online_lists?

    blended = Archetypes::MetagameScope.call(archetype: archetype,
                                             pool_param: Archetypes::MetagameScope::ALL)

    assert_equal [ 3, 1 ], [ blended.lists_count, blended.online_lists_count ]
    assert_predicate blended, :online_lists?
  end

  # A sample of paper events must say nothing about online play — a "0 online lists" line on an
  # archetype nobody has imported an online result for is noise that reads as a warning.
  test "a sample holding no online event reports zero and answers online_lists? false" do
    archetype = archetype_of_its_own
    event = standard_event(pool: standard_pools(:twm_por), date: Date.new(2026, 5, 1))
    2.times { record(event, archetype, deck: field_list) }

    result = Archetypes::MetagameScope.call(archetype: archetype)

    assert_equal 2, result.lists_count
    assert_equal 0, result.online_lists_count
    refute_predicate result, :online_lists?
  end

  # COUNT(DISTINCT deck_id) and not COUNT(*): an online standing with no list is a standing, not a
  # list, and the selector's sentence is about the card report's denominator.
  test "an online standing with no list is not counted as an online list" do
    archetype = archetype_of_its_own
    pool = standard_pools(:twm_por)
    online = online_event(pool: pool, date: Date.new(2026, 5, 1))
    record(online, archetype)
    record(online, archetype, deck: field_list)

    result = Archetypes::MetagameScope.call(archetype: archetype)

    assert_equal 2, result.standings.count
    assert_equal 1, result.lists_count
    assert_equal 1, result.online_lists_count
  end

  test "an archetype nobody has recorded yields no options but All formats and no pool" do
    result = Archetypes::MetagameScope.call(archetype: archetype_of_its_own)

    assert_equal [ Archetypes::MetagameScope::ALL ], result.options.map(&:value)
    assert_equal "All formats — 0 lists", result.options.sole.label
    assert_equal [ 0, 0 ], [ result.lists_count, result.standings.count ]
    assert_predicate result, :no_lists?
  end

  # ---- the venue axis (#160) ----

  # The fold, in absolute terms rather than as a comparison between two venue states. Unfolded, a
  # blended pool yields two buckets and the selector offers "pool — 8 lists" beside
  # "pool — 20 lists" in one <select>; both venue states carry that duplicate, so a test comparing
  # the two passes with the bug in place. Hence the literal, twice.
  test "a blended pool is one option carrying its whole total, whatever venue is selected" do
    archetype, pool = blended(paper: 8, online: 20)
    expected = [ [ pool.id.to_s, "#{pool.name} — 28 lists", 28 ],
                 [ Archetypes::MetagameScope::ALL, "All formats — 28 lists", 28 ] ]

    [ nil, "paper", "online" ].each do |venue|
      result = Archetypes::MetagameScope.call(archetype: archetype, venue_param: venue)

      assert_equal expected, result.options.map { |o| [ o.value, o.label, o.lists_count ] },
        "the pool options moved under venue=#{venue.inspect}"
    end
  end

  # The counts themselves, as literals. Their *sum* is not a testable statement about the fold —
  # the pool total and the two halves all come out of it, so any fold satisfies the identity.
  test "each venue counts its own half, and All counts both" do
    archetype, = blended(paper: 8, online: 20)

    assert_equal [ 28, 8, 20 ], [ nil, "paper", "online" ].map { |venue|
      Archetypes::MetagameScope.call(archetype: archetype, venue_param: venue).lists_count
    }
  end

  # The one shape the fold gets wrong, named rather than left to a measurement that is true today:
  # one deck carrying a standing under each venue is counted twice in the pool total. Measured on
  # the production data, 0 decks are in that shape and 0 carry more than one standing at all, but
  # index_tournament_standings_on_deck_id is not unique so nothing forbids it. The venue-filtered
  # counts stay exact, because each is a single cell.
  test "one deck under both venues is over-counted in the pool total and exact within a venue" do
    archetype = archetype_of_its_own
    pool = standard_pools(:twm_por)
    shared = field_list
    record(standard_event(pool: pool, date: Date.new(2026, 5, 1)), archetype, deck: shared)
    record(online_event(pool: pool, date: Date.new(2026, 5, 2)), archetype, deck: shared)

    blended = Archetypes::MetagameScope.call(archetype: archetype)

    assert_equal 1, blended.standings.distinct.count(:deck_id), "the sample really holds one deck"
    assert_equal 2, blended.lists_count, "the documented over-count changed shape"
    assert_equal [ 1, 1 ], [ "paper", "online" ].map { |venue|
      Archetypes::MetagameScope.call(archetype: archetype, venue_param: venue).lists_count
    }
  end

  # `pool_id` is overloaded: nil means "every pool" as a selection and "the non-Standard bucket"
  # as data. Every venue figure reads it as the selection — read the other way, this archetype's
  # venue control would answer over the GLC bucket alone. Measured, 24 of the 48 archetypes
  # carrying a list have a blended All-formats sample, so this is the majority state.
  test "All formats counts venues over every pool, not over the non-Standard bucket" do
    archetype = archetype_of_its_own
    old_pool = standard_pools(:twm_asc)
    new_pool = standard_pools(:twm_por)
    3.times { record(standard_event(pool: old_pool, date: Date.new(2025, 6, 1)), archetype, deck: field_list) }
    2.times { record(online_event(pool: new_pool, date: Date.new(2026, 5, 1)), archetype, deck: field_list) }
    record(unpooled_event(date: Date.new(2026, 4, 1)), archetype, deck: field_list)

    result = Archetypes::MetagameScope.call(archetype: archetype,
                                            pool_param: Archetypes::MetagameScope::ALL)

    assert_predicate result, :venue_selectable?
    assert_equal [ 6, 4, 2 ], result.venue_options.map(&:lists_count)
    assert_equal [ "All — 6 lists", "Paper — 4 lists", "Online — 2 lists" ],
      result.venue_options.map(&:label)
  end

  # Three options are always rendered, so `venue_options.size > 1` is always true and says nothing.
  # The question is whether the selection holds both venues at all.
  test "venue_selectable? is false on a one-venue selection and true on a blended one" do
    paper_only = archetype_of_its_own
    2.times { record(standard_event(pool: standard_pools(:twm_por), date: Date.new(2026, 5, 1)), paper_only, deck: field_list) }
    online_only = archetype_of_its_own
    2.times { record(online_event(pool: standard_pools(:twm_por), date: Date.new(2026, 5, 2)), online_only, deck: field_list) }
    both, = blended(paper: 2, online: 2)

    refute_predicate Archetypes::MetagameScope.call(archetype: paper_only), :venue_selectable?
    refute_predicate Archetypes::MetagameScope.call(archetype: online_only), :venue_selectable?
    assert_predicate Archetypes::MetagameScope.call(archetype: both), :venue_selectable?
  end

  # The shape that made `venue_selectable?` wrong, and the reason it needs its own test: for a
  # single pool "more than one non-empty cell" and "both venues" are the same question, because a
  # pool has at most a paper row and an online row. Under "All formats" they are not — the cells
  # span pools — so two paper-only samples in two pools counted as two cells and offered a Venue
  # select reading "All — 2 lists / Paper — 2 lists / Online — 0 lists": two labels for one sample
  # *and* a dead option that clamps back to All when clicked. Measured on the production data, one
  # archetype was in exactly this state (Mega Greninja ex / Dragapult ex).
  test "two pools of one venue are not a venue choice under All formats" do
    archetype = archetype_of_its_own
    2.times { record(standard_event(pool: standard_pools(:twm_asc), date: Date.new(2025, 6, 1)), archetype, deck: field_list) }
    record(unpooled_event(date: Date.new(2026, 4, 1)), archetype, deck: field_list)

    result = Archetypes::MetagameScope.call(archetype: archetype,
                                            pool_param: Archetypes::MetagameScope::ALL)

    assert_equal 2, result.venue_options.count { |option| option.lists_count.positive? },
      "sanity: two cells, both paper, so only All and Paper hold anything"
    refute_predicate result, :venue_selectable?
  end

  # And the mirror, so the fix cannot be "always false under All formats": two pools where one of
  # them is blended is a real choice, and its options carry the grand totals.
  test "a blended pool under All formats is still a venue choice" do
    archetype = archetype_of_its_own
    record(standard_event(pool: standard_pools(:twm_asc), date: Date.new(2025, 6, 1)), archetype, deck: field_list)
    record(standard_event(pool: standard_pools(:twm_por), date: Date.new(2026, 5, 1)), archetype, deck: field_list)
    record(online_event(pool: standard_pools(:twm_por), date: Date.new(2026, 5, 2)), archetype, deck: field_list)

    result = Archetypes::MetagameScope.call(archetype: archetype,
                                            pool_param: Archetypes::MetagameScope::ALL)

    assert_predicate result, :venue_selectable?
    assert_equal [ 3, 2, 1 ], result.venue_options.map(&:lists_count)
  end

  # The clamp, and both halves of it: a Result that kept the parameter would print an Online select
  # over a blended report, and a relation that stayed filtered would render an empty report under a
  # select reading All.
  test "a venue with no standing in the selected pool clamps to all, in the Result and the relation" do
    archetype = archetype_of_its_own
    paper_pool = standard_pools(:twm_asc)
    3.times { record(standard_event(pool: paper_pool, date: Date.new(2025, 6, 1)), archetype, deck: field_list) }
    record(online_event(pool: standard_pools(:twm_por), date: Date.new(2026, 5, 1)), archetype, deck: field_list)

    result = Archetypes::MetagameScope.call(archetype: archetype, pool_param: paper_pool.id.to_s,
                                            venue_param: "online")

    assert_equal :all, result.venue
    assert_equal 3, result.lists_count
    assert_equal 3, result.standings.count
  end

  # `?venue[]=online` is an Array and `?venue[a]=b` an ActionController::Parameters; the action is
  # reachable by anyone with a session. None may raise, and all fall back to the blended sample.
  # A Symbol is the one non-String that resolves, which is what the `to_s` in the initializer buys
  # — the guard is `VENUES.include?`, which fails closed on its own.
  test "a malformed venue parameter falls back to all, and a Symbol resolves" do
    archetype, = blended(paper: 4, online: 6)

    [ nil, "", "   ", "PAPER", "junk", [ "online" ], { a: 1 } ].each do |param|
      result = Archetypes::MetagameScope.call(archetype: archetype, venue_param: param)

      assert_equal :all, result.venue, "#{param.inspect} should fall back"
      assert_equal 10, result.lists_count
    end

    assert_equal :online, Archetypes::MetagameScope.call(archetype: archetype,
                                                         venue_param: :online).venue
  end

  # The figures, not their equality: under `:online` both `lists_count` and `online_lists_count`
  # are the same sum over the same rows, so asserting they match holds for any value.
  test "online_lists_count describes the sample the venue selected" do
    archetype, = blended(paper: 8, online: 20)

    assert_equal [ [ 28, 20 ], [ 8, 0 ], [ 20, 20 ] ],
      [ nil, "paper", "online" ].map { |venue|
        result = Archetypes::MetagameScope.call(archetype: archetype, venue_param: venue)
        [ result.lists_count, result.online_lists_count ]
      }
  end

  # The threshold refused in the design, from the other side: a venue half under SMALL_SAMPLE is a
  # small sample and says so, rather than being hidden behind a control that refuses to offer it.
  test "a venue half below the threshold is a small sample even though the pool is not" do
    archetype, = blended(paper: 8, online: 20)

    blended_result = Archetypes::MetagameScope.call(archetype: archetype)
    paper = Archetypes::MetagameScope.call(archetype: archetype, venue_param: "paper")

    refute_predicate blended_result, :small_sample?
    assert_predicate paper, :small_sample?
    assert_predicate paper, :fuller_sample_available?
  end

  # Both relations, because the card report reads one and the performance panel the other: a filter
  # applied to `standings` alone would narrow the panel and leave the report blended, which is the
  # two-populations disagreement this service exists to prevent.
  test "a venue narrows both relations, and an unlisted standing stays out of the listed one" do
    archetype, pool = blended(paper: 2, online: 3)
    record(online_event(pool: pool, date: Date.new(2026, 6, 1)), archetype, deck: nil)

    online = Archetypes::MetagameScope.call(archetype: archetype, venue_param: "online")

    assert_equal 4, online.standings.count
    assert_equal 3, online.listed_standings.count
    assert_equal 2, Archetypes::MetagameScope.call(archetype: archetype,
                                                   venue_param: "paper").standings.count
  end

  test "an archetype nobody has recorded offers no venue choice and clamps to all" do
    result = Archetypes::MetagameScope.call(archetype: archetype_of_its_own, venue_param: "online")

    assert_equal :all, result.venue
    refute_predicate result, :venue_selectable?
    assert_equal [ 0, 0, 0 ], result.venue_options.map(&:lists_count)
  end

  # Helpers, deliberately below `private`: a `test` declared under it never runs, which is why
  # everything above this line is a test and everything below it is not.
  private

  SET_NAME = "MGS".freeze

  def archetype_of_its_own
    Archetype.create!(primary_card: trainer("Metagame Marker #{next_index}"))
  end

  def trainer(name, subtype: "Item")
    Card.create!(name: name, card_type: "Trainer", set_name: SET_NAME,
                 set_number: next_index.to_s, rarity: "Uncommon", subtype: subtype)
  end

  # A Standard event has to carry a pool, and (name_normalized, date) is UNIQUE — hence the
  # per-test counter in the name, which keeps these clear of the two catalogued fixtures.
  def standard_event(pool:, date:, tier: "regional")
    Tournament.create!(name: "Metagame Event #{next_index}", date: date, format: "standard",
                       standard_pool: pool, tier: tier, created_by: users(:one))
  end

  # Anchored to a real pool, like the import writes them: the whole point is that an online event
  # is indistinguishable from a paper one on the axis this service buckets by.
  def online_event(pool:, date:)
    Tournament.create!(name: "Metagame Event #{next_index}", date: date, format: "standard",
                       standard_pool: pool, tier: "other", online: true, created_by: users(:one))
  end

  def unpooled_event(date:, tier: "league_cup")
    Tournament.create!(name: "Metagame Event #{next_index}", date: date, format: "glc",
                       tier: tier, created_by: users(:one))
  end

  def record(event, archetype, deck: nil, division: "masters", placement: nil)
    TournamentStanding.create!(tournament: event, archetype: archetype, deck: deck,
                               player_name: "Player #{next_index}", division: division,
                               placement: placement, created_by: users(:one))
  end

  # An ownerless deck is a tournament field list: shared (the only listing that can show it) and
  # never physical (there is no collection for it to consume).
  def field_list
    Deck.create!(name: "Field list #{next_index}", user: nil, shared: true, physical: false,
                 format: "glc")
  end

  # One archetype, one pool, both venues — the shape the venue control exists for, and the one
  # 24 of the 48 production archetypes are in. A distinct field list per standing, so `lists` and
  # `standings` cannot agree by accident.
  def blended(paper:, online:, pool: standard_pools(:twm_por))
    archetype = archetype_of_its_own
    paper.times { record(standard_event(pool: pool, date: Date.new(2026, 5, 1)), archetype, deck: field_list) }
    online.times { record(online_event(pool: pool, date: Date.new(2026, 5, 2)), archetype, deck: field_list) }
    [ archetype, pool ]
  end

  def next_index
    @next_index = @next_index.to_i + 1
  end
end
