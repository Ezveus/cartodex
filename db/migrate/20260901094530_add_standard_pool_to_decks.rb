class AddStandardPoolToDecks < ActiveRecord::Migration[8.1]
  def change
    # Nullable in the database: the column is required by validation only when the
    # format is Standard, exactly like other_format_name is for "other".
    add_reference :decks, :standard_pool, foreign_key: true
  end
end
