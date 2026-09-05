module Archetypes
  # The three numbers and the date the archetype index prints per row, for a whole page of rows in
  # one grouped query.
  #
  # Not a counter_cache: three of the four are not plain row counts (distinct events, standings
  # carrying a list, the latest event's date), and a cache column would have to be maintained by
  # every path that writes a standing — the bulk importer, its undo, the wiki-editable standings
  # controller and the cascade that takes a sheet down with its event.
  class IndexCounts < ApplicationService
    Counts = Struct.new(:standings, :events, :lists, :last_event_on, keyword_init: true) do
      def self.zero = new(standings: 0, events: 0, lists: 0, last_event_on: nil)
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
          Arel.sql("MAX(tournaments.date)")
        )
        .to_h do |archetype_id, standings, events, lists, last_on|
          [ archetype_id, Counts.new(standings: standings, events: events, lists: lists,
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
