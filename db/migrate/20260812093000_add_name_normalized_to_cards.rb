class AddNameNormalizedToCards < ActiveRecord::Migration[8.1]
  # Isolated from app/models/card.rb on purpose: this backfill must keep working
  # whatever that class grows into.
  class MigrationCard < ActiveRecord::Base
    self.table_name = "cards"
  end

  # No index: every read of this column is a `LIKE '%…%'` substring match, whose
  # leading wildcard makes a b-tree index unusable. An index would only cost
  # writes on the card scrapes.
  def up
    add_column :cards, :name_normalized, :string

    # Backfilled in Ruby rather than with SQL `lower()`: SQLite's `lower()` only
    # folds ASCII A–Z, which is exactly the case-folding gap this column exists
    # to close. Ruby's String#downcase applies full Unicode case mapping.
    MigrationCard.reset_column_information
    MigrationCard.find_each { |card| card.update_columns(name_normalized: card.name&.downcase) }
  end

  def down
    remove_column :cards, :name_normalized
  end
end
