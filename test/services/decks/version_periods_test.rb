require "test_helper"

module Decks
  class VersionPeriodsTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      @deck = @user.decks.create!(name: "Periods", standard_pool: standard_pools(:twm_por))
      @v1 = version(10.days.ago)
      @v2 = version(5.days.ago)
    end

    test "a version's period is the span of its results' played_at, counted" do
      played(@v1, Time.zone.local(2026, 3, 22, 21))
      played(@v1, Time.zone.local(2026, 3, 17, 10))
      played(@v1, Time.zone.local(2026, 3, 19, 10))

      period = VersionPeriods.call([ @v1 ])[@v1.id]

      assert_equal Date.new(2026, 3, 17), period.first_on
      assert_equal Date.new(2026, 3, 22), period.last_on
      assert_equal 3, period.results
      assert_equal 0, period.entries
    end

    # A participation says the list was played that day even before any match of it is logged, so
    # it widens the dates — and it is counted apart, never as a match.
    test "a participation's tournament date counts toward the dates, not the match count" do
      played(@v1, Time.zone.local(2026, 3, 20, 10))
      @user.tournament_entries.create!(tournament: tournaments(:two), deck: @deck, deck_version: @v1)

      period = VersionPeriods.call([ @v1 ])[@v1.id]

      assert_equal tournaments(:two).date, period.first_on
      assert_equal Date.new(2026, 3, 20), period.last_on
      assert_equal 1, period.results
      assert_equal 1, period.entries
    end

    # The app's zone, not UTC: a match played at 00:30 in Paris is played that day.
    test "dates are read in the application's time zone" do
      played(@v1, Time.zone.local(2026, 3, 17, 0, 30))

      assert_equal Date.new(2026, 3, 17), VersionPeriods.call([ @v1 ])[@v1.id].first_on
    end

    test "every version given has a period, an empty one when nothing is filed on it" do
      played(@v1, Time.zone.local(2026, 3, 17, 10))

      periods = VersionPeriods.call([ @v1, @v2 ])

      assert_equal [ @v1.id, @v2.id ].sort, periods.keys.sort
      assert_equal VersionPeriods::Period.new(nil, nil, 0, 0), periods[@v2.id]
    end

    test "another version's results stay on that version" do
      played(@v1, Time.zone.local(2026, 3, 17, 10))
      played(@v2, Time.zone.local(2026, 3, 25, 10))

      periods = VersionPeriods.call([ @v1, @v2 ])

      assert_equal Date.new(2026, 3, 17), periods[@v1.id].last_on
      assert_equal Date.new(2026, 3, 25), periods[@v2.id].first_on
    end

    test "costs at most two queries, whatever the number of versions" do
      played(@v1, Time.zone.local(2026, 3, 17, 10))
      small = ActiveRecord::Base.uncached { count_queries { VersionPeriods.call([ @v1 ]) } }

      v3 = version(2.days.ago)
      [ @v2, v3 ].each { |v| played(v, Time.zone.local(2026, 3, 18, 10)) }
      @user.tournament_entries.create!(tournament: tournaments(:two), deck: @deck, deck_version: v3)
      large = ActiveRecord::Base.uncached { count_queries { VersionPeriods.call([ @v1, @v2, v3 ]) } }

      assert_operator small, :<=, 2
      assert_equal small, large
    end

    test "no version, no query" do
      assert_equal({}, VersionPeriods.call([]))
      assert_equal 0, count_queries { VersionPeriods.call([]) }
    end

    private

    # A result whose played_at was cleared from the edit form still counts: the version was played,
    # the page just cannot say when.
    test "a result with no played_at is counted without inventing a date" do
      @deck.deck_results.create!(result: "win", played_at: nil, deck_version: @v1)

      period = VersionPeriods.call([ @v1 ])[@v1.id]

      assert_nil period.first_on
      assert_nil period.last_on
      assert_equal 1, period.results
    end

    # An event still to come is not a time the list was played.
    test "a participation at an event still to come does not date the version" do
      tournament = Tournament.create!(name: "Next month's cup", date: Date.current + 30, format: "expanded")
      @user.tournament_entries.create!(tournament: tournament, deck: @deck, deck_version: @v1)

      period = VersionPeriods.call([ @v1 ])[@v1.id]

      assert_nil period.first_on
      assert_equal 0, period.entries
    end

    def version(effective_at)
      @deck.deck_versions.create!(effective_at: effective_at, format: "standard", standard_pool: standard_pools(:twm_por))
    end

    def played(version, at)
      @deck.deck_results.create!(result: "win", played_at: at, deck_version: version)
    end
  end
end
