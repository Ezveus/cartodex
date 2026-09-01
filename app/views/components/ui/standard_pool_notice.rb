module Ui
  # Tells the user their record is anchored to a Standard pool that is no longer
  # the one expected, and invites them to move it. Informative only: the anchor
  # is pinned by design (nothing moves it automatically, ever), and nothing here
  # writes it.
  #
  # `expected` is the pool the record would take if it were created now — the
  # current pool for a deck, the pool legal on its date for a tournament. Those
  # are different questions, and this component does not know which one it was
  # handed: a deck's mismatch is always staleness (expected is always the newest
  # pool the deck could have been anchored to), while a tournament's mismatch can
  # go either way (a data-entry error, not staleness). The wording below is
  # chosen by comparing the two pools' release dates rather than by asking what
  # kind of record this is, so it reads correctly either way.
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
        if stale?
          strong { @expected.name }
          plain " has released since — update it if you still play this deck."
        else
          plain "The pool for this date is "
          strong { @expected.name }
          plain " — check the anchor."
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
    def stale?
      @expected.released_on > @record.standard_pool.released_on
    end
  end
end
