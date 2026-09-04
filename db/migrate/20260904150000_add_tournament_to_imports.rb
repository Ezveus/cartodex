# An Import row says a background job is in flight; until now nothing said *what page* was
# waiting for it. TournamentsController#show listed every pending standing_list import the reader
# had, so a member who started a field list at event A and then opened event B saw B's
# "Importing…" section populated with A's row — and, since the item's DOM id is importing-<import
# id> and the completion broadcast removes it by that target, A's completion silently mutated B's
# page.
#
# Nullable and set by the standings controller alone: a deck or card_set import has no event, and
# this is deliberately *not* the tournament_standing_id a per-row spinner would need — the
# pending state still renders as one list beside the table, this only says which table.
class AddTournamentToImports < ActiveRecord::Migration[8.1]
  def change
    add_reference :imports, :tournament, null: true, foreign_key: true
  end
end
