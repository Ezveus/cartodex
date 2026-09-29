module DeckVersions
  # The words every surface uses to name a version: the two selects that move a result or a
  # participation onto one, the versions page, the diff page and the stats summary. One module so
  # that the option a reader picks reads the same as the row they chose it from.
  #
  # Every caller hands in a *numbered* version (`Deck#ordered_versions`): `#number` on one that
  # is not costs a COUNT per call, which a select of every version would pay once per option.
  #
  # A version's period is when it was *played* — its results and its participations, as
  # `Decks::VersionPeriods` reads them — and never its `effective_at`: that date only orders the
  # versions, and for every backfilled one it is an estimate, so printing it as a validity span
  # would state a period nobody ever played it in.
  module Labels
    module_function

    NOT_PLAYED = "not played yet".freeze
    DATE_UNKNOWN = "date unknown".freeze

    # "v2 — Standard (TEF-PBL) · played Sep 17 → 22". No year and no match count: an option has
    # to stay short enough for a phone's select, and the versions page carries the rest.
    def option(version, period = nil)
      "#{version.label} — #{version.format_label} · #{played(period, year: false, count: false)}"
    end

    # "played Sep 17 → 22, 2026 · 5 matches". Only results are counted: a participation is an
    # event, not a match, so it can move the dates without adding to the count — and a version
    # played at an event nobody logged a match of prints its dates with no count at all.
    def played(period, year: true, count: true)
      return NOT_PLAYED if period.nil?
      # Matches whose played_at was cleared: counted, and said to be undated rather than unplayed.
      return undated(period, count:) if period.first_on.nil?

      text = "played #{span(period.first_on, period.last_on || period.first_on, year:)}"
      matches = tally(period.results)
      text += " · #{matches} #{matches == 1 ? "match" : "matches"}" if count && matches.positive?
      text
    end

    # The shared parts of the two ends are written once: "Sep 17 → 22, 2026", "Sep 28 → Oct 3,
    # 2026", and the year on both ends only when it differs.
    def span(first, last, year:)
      return day(first, year:) if first == last

      if first.year != last.year
        "#{day(first, year:)} → #{day(last, year:)}"
      elsif first.month != last.month
        "#{first.strftime("%b %-d")} → #{day(last, year:)}"
      else
        "#{first.strftime("%b %-d")} → #{year ? last.strftime("%-d, %Y") : last.strftime("%-d")}"
      end
    end

    # The contract names the field `results` without saying whether it holds the rows or their
    # count; both read the same here, and nil (nothing filed) reads as none.
    def undated(period, count:)
      matches = tally(period.results)
      return NOT_PLAYED unless matches.positive?
      return DATE_UNKNOWN unless count

      "#{matches} #{matches == 1 ? "match" : "matches"} · #{DATE_UNKNOWN}"
    end

    def tally(results)
      results.is_a?(Integer) ? results : Array(results).size
    end

    def day(date, year:)
      date.strftime(year ? "%b %-d, %Y" : "%b %-d")
    end
  end
end
