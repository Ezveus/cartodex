class AddSharedToDecks < ActiveRecord::Migration[8.1]
  def change
    add_column :decks, :shared, :boolean, null: false, default: false

    # [:shared, :created_at] rather than a partial index on `shared` alone: two of the
    # three readers order by created_at (the dashboard showcase and the paginated
    # /decks/shared), and an index on a single-valued boolean only enumerates rows — it
    # does not serve a sort. The third reader is a LIKE, which stays a scan regardless.
    add_index :decks, [ :shared, :created_at ]
  end
end
