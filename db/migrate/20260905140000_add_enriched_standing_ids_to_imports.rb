# The second half of a run's receipt. `created_standing_ids` records the rows a run *made*, which
# undo deletes; this records the rows it only *attached a field list to* — rows that existed
# before the run, typed by a member, and which undo must therefore not delete. Without it an
# enrich-only run was unundoable in both directions at once: the receipt was empty, so the Undo
# button did nothing, and `standing_params` does not permit `deck_id`, so the member whose row it
# was could not detach the list either — their only exit was destroying their own public standing.
class AddEnrichedStandingIdsToImports < ActiveRecord::Migration[8.1]
  def change
    change_table :imports do |t|
      t.json :enriched_standing_ids, null: false, default: []
    end
  end
end
