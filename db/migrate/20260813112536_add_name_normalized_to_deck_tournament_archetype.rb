class AddNameNormalizedToDeckTournamentArchetype < ActiveRecord::Migration[8.1]
  # Isolated from the app models on purpose: this backfill must keep working whatever those
  # classes grow into.
  class MigrationDeck < ActiveRecord::Base
    self.table_name = "decks"
  end

  class MigrationTournament < ActiveRecord::Base
    self.table_name = "tournaments"
  end

  class MigrationArchetype < ActiveRecord::Base
    self.table_name = "archetypes"
  end

  MODELS = [ MigrationDeck, MigrationTournament, MigrationArchetype ].freeze

  # No index: every read of this column is a `LIKE '%…%'` substring match, whose leading wildcard
  # makes a b-tree index unusable. This mirrors the choice made for cards.
  def up
    add_column :decks, :name_normalized, :string
    add_column :tournaments, :name_normalized, :string
    add_column :archetypes, :name_normalized, :string

    # Backfilled in Ruby rather than with SQL `lower()`: SQLite's `lower()` only folds ASCII A–Z,
    # which is exactly the case-folding gap this column exists to close. Ruby's String#downcase
    # applies full Unicode case mapping.
    MODELS.each do |model|
      model.reset_column_information
      model.find_each { |record| record.update_columns(name_normalized: record.name&.downcase) }
    end
  end

  def down
    remove_column :archetypes, :name_normalized
    remove_column :tournaments, :name_normalized
    remove_column :decks, :name_normalized
  end
end
