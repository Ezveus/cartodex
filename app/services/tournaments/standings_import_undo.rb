module Tournaments
  # Rolls back a bulk standings run (D12). Nothing else in the app can clean up after one: there
  # is no admin tournaments controller, an event becomes undeletable the moment a member records
  # a participation at it, and an ownerless field list is reachable for deletion through
  # TournamentStanding#destroy_ownerless_deck and nowhere else — while being listed publicly on
  # /decks/shared. So a bad import would otherwise be permanent.
  #
  # Two things it deliberately does not touch:
  #
  # - **a claimed standing.** A member who pressed "This is me" has adopted that row as their own
  #   published record; deleting it because an admin mis-ran an import would erase somebody
  #   else's work. It is counted and reported instead, so the admin knows the undo was partial.
  # - **the Tournament rows the run created.** An empty catalog entry is harmless, and one that
  #   another member has since attached an entry or a hand-typed standing to is not this button's
  #   to delete.
  #
  # The field lists go with their standings for free: TournamentStanding's `before_destroy
  # :destroy_ownerless_deck` already takes an unowned deck with the row, and that guard — not a
  # deck delete written here — is what keeps a member's own deck out of reach.
  class StandingsImportUndo < ApplicationService
    # `destroyed` is what this call actually removed, `detached` the field lists it took back off
    # rows it did not create, `kept_claimed` what it found and left. Counts and not id lists: the
    # admin flash names numbers, and the ids that still matter stay on the Import itself.
    Result = Struct.new(:destroyed, :detached, :kept_claimed, keyword_init: true)

    def initialize(import)
      @import = import
    end

    def call
      unless @import.kind == "limitless_standings"
        raise ArgumentError,
          "only a limitless_standings import records the standings it created (got #{@import.kind.inspect})"
      end

      # Rows that no longer exist are simply absent from this relation: a member may have deleted
      # one by hand in the meantime — standings are wiki-governed — and an undo is not the place
      # to notice that.
      recorded = TournamentStanding.where(id: @import.created_standing_ids).to_a
      claimed, unclaimed = recorded.partition { |standing| standing.tournament_entry_id.present? }
      enriched = TournamentStanding.where(id: @import.enriched_standing_ids).to_a

      serialized_transaction do
        unclaimed.each(&:destroy!)
        enriched.each { |standing| detach_field_list(standing) }
        # Only the ids actually destroyed are struck off. A claimed row keeps its id on the
        # receipt on purpose: the claim may later be severed with "Unlink", and a second undo
        # should then be able to finish the job. Since nothing was destroyed for it, running undo
        # twice in a row destroys nothing the second time and still reports the same rows it kept
        # — a no-op, not a double count.
        @import.update!(
          created_standing_ids: @import.created_standing_ids - unclaimed.map(&:id),
          enriched_standing_ids: @import.enriched_standing_ids - enriched.map(&:id)
        )
      end

      Result.new(destroyed: unclaimed.size, detached: enriched.size, kept_claimed: claimed.size)
    end

    private

    # An enriched row existed before the run and belongs to whoever typed it: the run added a field
    # list and that is all it may take back. `update_column` for the reason
    # Tournaments::StandingsController#unclaim uses it — severing a link has no business asking
    # whether the rest of a wiki-editable row still validates, and a placement invalidated since by
    # a shrunk field size would otherwise make the row un-undoable. The deck goes only if nobody
    # owns it, the same guard TournamentStanding#destroy_ownerless_deck applies.
    def detach_field_list(standing)
      deck = standing.deck
      standing.update_column(:deck_id, nil)
      deck&.destroy_if_ownerless
    end
  end
end
