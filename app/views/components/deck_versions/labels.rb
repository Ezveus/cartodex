module DeckVersions
  # The words every surface uses to name a version: the two selects that move a result or a
  # participation onto one, the versions page and the stats summary. One module so that the
  # option a reader picks reads the same as the row they chose it from.
  #
  # Every caller hands in a *numbered* version (`Deck#ordered_versions`): `#number` on one that
  # is not costs a COUNT per call, which a select of every version would pay once per option.
  module Labels
    module_function

    # The date alone: `effective_at` is an estimate for every backfilled version (the moment the
    # list was last edited), so printing it to the minute would claim a precision it never had.
    def date(version)
      I18n.l(version.effective_at.to_date, format: :long)
    end

    def option(version)
      "#{version.label} — #{version.format_label}, from #{date(version)}"
    end

    # A version lasts until the next one starts; the latest has no end yet.
    def period(version, following)
      return "since #{date(version)}" unless following

      "#{date(version)} → #{date(following)}"
    end
  end
end
