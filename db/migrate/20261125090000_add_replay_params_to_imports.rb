# What an import was run with, so /admin/imports can run it again (Imports::Replayer). Until now a
# row kept only its kind and label, and the label rebuilds the whole job for one kind alone: a card
# set, whose label is the set code its Limitless URL ends in. That kind is backfilled here, which is
# what keeps every card-set row that Retry could replay replayable. Every other pre-existing row
# keeps `{}` — what it was run from is genuinely gone — and gets no Reimport button.
class AddReplayParamsToImports < ActiveRecord::Migration[8.1]
  def up
    add_column :imports, :replay_params, :json, null: false, default: {}
    backfill_card_sets
  end

  def down
    remove_column :imports, :replay_params
  end

  # Public so a test can run it against rows it built: CI loads db/schema.rb and never runs a
  # migration, so this statement is otherwise executed by nothing in the suite.
  def backfill_card_sets
    execute <<~SQL
      UPDATE imports
      SET replay_params = json_object('url', 'https://limitlesstcg.com/cards/' || label)
      WHERE kind = 'card_set'
    SQL
  end
end
