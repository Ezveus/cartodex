module Ui
  # Tells the user their record is anchored to a Standard pool that is no longer
  # the one expected, and invites them to move it. Informative only: the anchor
  # is pinned by design (nothing moves it automatically, ever), and nothing here
  # writes it.
  #
  # `expected` is the pool the record would take if it were created now — the
  # current pool for a deck, the pool legal on its date for a tournament. Those
  # are different questions, and this component does not know which one it was
  # handed — and neither branch's copy may name a record type or mention a date:
  # a deck has no date, and a tournament's mismatch can go either direction (its
  # anchor may be older *or* newer than the pool its date calls for). So every
  # string this component can ever emit must read correctly for both a deck and
  # a tournament. The branch below is decided purely by comparing the two
  # StandardPool#released_on values it already holds, never by asking what kind
  # of record this is.
  class StandardPoolNotice < ApplicationComponent
    def initialize(record:, expected:)
      @record = record
      @expected = expected
    end

    def view_template
      return unless applicable?

      div(class: "form-hint standard-pool-notice") do
        plain "Anchored to "
        strong { @record.standard_pool.name }
        plain ". "
        strong { @expected.name }
        if stale?
          plain " has released since — update the anchor if this is still current."
        else
          plain " is the pool that applies — check the anchor."
        end
      end
    end

    private

    # Never on a creation form, where there is nothing to be stale about. Never
    # without an existing anchor either — that is the pre-backfill state, not
    # staleness.
    def applicable?
      @record.persisted? && @expected.present? &&
        @record.standard_pool.present? && @record.standard_pool_id != @expected.id
    end

    # True when the expected pool released after the anchor's — the ordinary
    # "a newer Standard exists" case. False covers the other direction, which
    # only a tournament anchored to the wrong pool for its date can produce.
    #
    # Strict `>`: released_on carries no uniqueness constraint, so two pools
    # sharing a release date would fall to the "else" branch instead of this
    # one. Harmless — neither branch names a record type or a date, so both
    # read correctly regardless of which one a same-day tie lands in.
    def stale?
      @expected.released_on > @record.standard_pool.released_on
    end
  end
end
