module Decks
  # When each version was actually played: the span of its results' played_at and its
  # participations' tournament dates. effective_at orders and numbers versions, but a list imported
  # after the fact, or recorded the day a result was logged, says nothing true about when it was on
  # the table — matches do.
  #
  # Participations widen the dates and are counted apart: an event says the list was played that
  # day even before a single match of it is logged, and it is not a match.
  #
  # Two grouped queries whatever the number of versions, so a page listing a deck's whole history
  # pays the same for one version as for twenty.
  class VersionPeriods < ApplicationService
    # first_on/last_on are Dates, nil when nothing is filed on the version; results/entries count.
    Period = Struct.new(:first_on, :last_on, :results, :entries)

    def initialize(versions)
      @ids = versions.map { |version| version.respond_to?(:id) ? version.id : version }
    end

    # No guard for an empty list: `where(deck_version_id: [])` issues no query at all.
    def call
      periods = @ids.index_with { Period.new(nil, nil, 0, 0) }
      result_spans.each { |id, first, last, count| widen(periods[id], first, last, results: count) }
      entry_spans.each { |id, first, last, count| widen(periods[id], first, last, entries: count) }
      periods
    end

    private

    # played_at is a datetime: read in the application's zone, the day a Paris player sees on the
    # clock, not the UTC one it is stored in.
    def result_spans
      played_at = DeckResult.type_for_attribute(:played_at)

      DeckResult.where(deck_version_id: @ids).group(:deck_version_id)
        .pluck(:deck_version_id, Arel.sql("MIN(deck_results.played_at)"), Arel.sql("MAX(deck_results.played_at)"), Arel.sql("COUNT(*)"))
        .map { |id, first, last, count| [ id, to_date(played_at, first), to_date(played_at, last), count ] }
    end

    # An event still to come is not a time the list was played, so it neither dates nor counts.
    def entry_spans
      date = Tournament.type_for_attribute(:date)

      TournamentEntry.joins(:tournament).where(deck_version_id: @ids)
        .where(tournaments: { date: ..Date.current }).group(:deck_version_id)
        .pluck(:deck_version_id, Arel.sql("MIN(tournaments.date)"), Arel.sql("MAX(tournaments.date)"), Arel.sql("COUNT(*)"))
        .map { |id, first, last, count| [ id, to_date(date, first), to_date(date, last), count ] }
    end

    # SQLite hands an aggregate back as text, which pluck cannot type from a column it does not
    # know; the attribute's own type reads it the way the model would.
    def to_date(type, value)
      type.deserialize(value)&.to_date
    end

    def widen(period, first, last, results: 0, entries: 0)
      period.first_on = [ period.first_on, first ].compact.min
      period.last_on = [ period.last_on, last ].compact.max
      period.results += results
      period.entries += entries
    end
  end
end
