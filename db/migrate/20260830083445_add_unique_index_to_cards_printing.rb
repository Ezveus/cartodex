class AddUniqueIndexToCardsPrinting < ActiveRecord::Migration[8.1]
  # `Cards::Fetcher` identifies a printing with `find_by(set_name:, set_number:)`
  # and has always assumed that tuple names at most one row — but nothing
  # enforced it, so two concurrent imports of the same card could each miss and
  # each insert. That was survivable while every card was re-scraped daily; now
  # that a known printing is never re-fetched, whichever duplicate the lookup
  # happens to return is the one the app keeps using, permanently.
  #
  # Raw SQL rather than the Card model on purpose: a migration must keep meaning
  # what it meant when it ran, and the model will move on.
  def up
    duplicates = select_all(<<~SQL).to_a
      SELECT set_name, set_number, COUNT(*) AS occurrences
      FROM cards
      GROUP BY set_name, set_number
      HAVING COUNT(*) > 1
      ORDER BY occurrences DESC
    SQL

    if duplicates.any?
      listed = duplicates.first(5).map { |row| "#{row['set_name']} #{row['set_number']} (×#{row['occurrences']})" }
      raise "Cannot add a unique index on (set_name, set_number): #{duplicates.size} printing(s) " \
            "appear more than once — #{listed.join(', ')}#{'…' if duplicates.size > 5}. " \
            "Merge them first; deck_cards and collections may point at either row, so dropping " \
            "one blindly would silently move somebody's cards."
    end

    add_index :cards, [ :set_name, :set_number ], unique: true
  end

  def down
    remove_index :cards, [ :set_name, :set_number ]
  end
end
