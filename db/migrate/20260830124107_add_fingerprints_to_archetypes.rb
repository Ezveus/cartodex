class AddFingerprintsToArchetypes < ActiveRecord::Migration[8.1]
  # `(primary_card_id, secondary_card_id)` is UNIQUE but does not do what it looks
  # like it does: SQLite treats NULLs as distinct, so two archetypes sharing a
  # primary and holding no secondary are accepted by the database. Only the model
  # validation has been stopping them.
  #
  # Identity is really the pair of *fingerprints* — two archetypes built from two
  # printings of the same cards are duplicates, not siblings — so the index moves
  # onto denormalised copies of them, and a missing secondary is the empty string
  # rather than NULL so the pair is always fully comparable.
  #
  # Raw SQL rather than the Archetype model on purpose: a migration must keep
  # meaning what it meant when it ran, and the model will move on.
  def up
    add_column :archetypes, :primary_fingerprint, :string
    add_column :archetypes, :secondary_fingerprint, :string, null: false, default: ""

    execute <<~SQL
      UPDATE archetypes
      SET primary_fingerprint = (
            SELECT fingerprint FROM cards WHERE cards.id = archetypes.primary_card_id
          ),
          secondary_fingerprint = COALESCE(
            (SELECT fingerprint FROM cards WHERE cards.id = archetypes.secondary_card_id), ''
          )
    SQL

    reject_unfingerprinted!
    reject_duplicates!

    change_column_null :archetypes, :primary_fingerprint, false
    remove_index :archetypes, name: "index_archetypes_on_card_pair"
    add_index :archetypes, [ :primary_fingerprint, :secondary_fingerprint ],
      unique: true, name: "index_archetypes_on_fingerprint_pair"
  end

  def down
    remove_index :archetypes, name: "index_archetypes_on_fingerprint_pair"
    add_index :archetypes, [ :primary_card_id, :secondary_card_id ],
      unique: true, name: "index_archetypes_on_card_pair"
    remove_column :archetypes, :secondary_fingerprint
    remove_column :archetypes, :primary_fingerprint
  end

  # Public so a test can exercise it: once the unique index below exists, a
  # duplicate pair is impossible to create, and there is no other way to run the
  # query that is supposed to find one.
  def duplicate_pairs
    select_all(<<~SQL).to_a
      SELECT GROUP_CONCAT(id) AS ids, GROUP_CONCAT(name, ' / ') AS names
      FROM archetypes
      GROUP BY primary_fingerprint, secondary_fingerprint
      HAVING COUNT(*) > 1
    SQL
  end

  private

  # "" means "no secondary": a *present* secondary_card_id with a blank
  # secondary_fingerprint is a card that has never been scraped, not a missing
  # secondary, and must be caught here too — otherwise it migrates quietly into
  # looking single-member and can collide with an unrelated single-member
  # archetype on the same primary.
  def reject_unfingerprinted!
    orphans = select_all(<<~SQL).to_a
      SELECT id, name,
        CASE WHEN primary_fingerprint IS NULL OR primary_fingerprint = '' THEN 'primary' ELSE 'secondary' END AS missing_half
      FROM archetypes
      WHERE primary_fingerprint IS NULL OR primary_fingerprint = ''
         OR (secondary_card_id IS NOT NULL AND secondary_fingerprint = '')
    SQL
    return if orphans.empty?

    raise "#{orphans.size} archetype(s) point at a card with no fingerprint and cannot be " \
          "keyed on one — #{orphans.map { |row| "##{row['id']} #{row['name']} (#{row['missing_half']})" }.join(', ')}. " \
          "Re-scrape those cards from the admin panel first (Cards → Rescrape), which is what " \
          "computes a fingerprint."
  end

  def reject_duplicates!
    duplicates = duplicate_pairs
    return if duplicates.empty?

    listed = duplicates.map { |row| "  #{row['ids']} — #{row['names']}" }.join("\n")
    raise "#{duplicates.size} archetype fingerprint pair(s) are duplicated, so the unique index " \
          "cannot be added:\n#{listed}\n" \
          "Merge them by hand first. This migration will not pick one to delete: decks and " \
          "deck_results point at these rows, so dropping one would silently move somebody's data."
  end
end
