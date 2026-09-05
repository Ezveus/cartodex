module Archetypes
  # The three numbers and the date the archetype index prints per row, plus the two that say how
  # much of them came from online play, for a whole page of rows in one grouped query.
  #
  # Not a counter_cache: most of them are not plain row counts (distinct events, standings
  # carrying a list, the latest event's date, either online figure), and a cache column would have
  # to be maintained by
  # every path that writes a standing — the bulk importer, its undo, the wiki-editable standings
  # controller and the cascade that takes a sheet down with its event.
  class IndexCounts < ApplicationService
    # `online_standings` qualifies the whole row rather than any one of the other three: an
    # imported online event contributes a standing, a distinct event, a list *and* possibly the
    # latest date, so annotating one figure would imply the rest are clean. Measured on the first
    # archetype to carry both sources: 106 standings and 16 events, of which 13 and 13 are online
    # — the events column is the one the blend distorts most, and the ordering key is standings,
    # so there is no single figure the note could honestly sit beside.
    Counts = Struct.new(:standings, :events, :lists, :online_standings, :online_events,
      :last_event_on, keyword_init: true) do
      def self.zero = new(standings: 0, events: 0, lists: 0, online_standings: 0, online_events: 0,
                          last_event_on: nil)

      def online? = online_standings.positive?
    end

    def initialize(archetype_ids:)
      @archetype_ids = Array(archetype_ids).uniq
    end

    # Archetype id => Counts, with a zero entry for every id asked about, so a caller never has to
    # tell "no standings" from "absent from the Hash" — the index lists archetypes nobody has
    # recorded a result for, and they are the majority.
    def call
      return {} if @archetype_ids.empty?

      counted = TournamentStanding
        .where(archetype_id: @archetype_ids)
        .joins(:tournament)
        .group(:archetype_id)
        .pluck(
          Arel.sql("tournament_standings.archetype_id"),
          Arel.sql("COUNT(*)"),
          Arel.sql("COUNT(DISTINCT tournament_standings.tournament_id)"),
          # DISTINCT because two standings may point at one deck (the deck_id index is not
          # unique), and this column has to agree with the "N lists" the archetype's own page
          # prints for the same archetype.
          Arel.sql("COUNT(DISTINCT tournament_standings.deck_id)"),
          # A term in the query that is already grouped and already joins tournaments, not a
          # second query: /archetypes is pinned at a flat 7 queries by its own test, and this
          # column is printed for every row of every page.
          Arel.sql("SUM(CASE WHEN tournaments.online THEN 1 ELSE 0 END)"),
          Arel.sql("COUNT(DISTINCT CASE WHEN tournaments.online THEN tournaments.id END)"),
          Arel.sql("MAX(tournaments.date)")
        )
        .to_h do |archetype_id, standings, events, lists, online_standings, online_events, last_on|
          [ archetype_id, Counts.new(standings: standings, events: events, lists: lists,
                                     online_standings: online_standings, online_events: online_events,
                                     last_event_on: to_date(last_on)) ]
        end

      @archetype_ids.index_with { |id| counted[id] || Counts.zero }
    end

    private

    # MAX() over a date column comes back as a String from SQLite: an aggregate carries no column
    # type for Rails to cast from.
    def to_date(value)
      value.is_a?(String) ? Date.parse(value) : value
    end
  end
end
