class AddIndexOnTournamentsDate < ActiveRecord::Migration[8.1]
  def change
    # /tournaments is public, paginated and ordered by `date DESC`. The table's other indexes
    # are `created_by_id` and the `(name_normalized, date)` UNIQUE key, whose leading column is
    # wrong for that sort — so every anonymous catalog request sorted the whole table. Same
    # reasoning as `[:shared, :created_at]` on decks (20260902155701), and the same doctrine the
    # /cards story in CLAUDE.md states: remove the amplifier before rationing it, not after.
    # The `LIKE '%…%'` search stays a scan either way, as NameNormalizable already documents.
    add_index :tournaments, :date
  end
end
