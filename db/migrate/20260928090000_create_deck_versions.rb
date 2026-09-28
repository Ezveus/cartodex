class CreateDeckVersions < ActiveRecord::Migration[8.1]
  def up
    create_table :deck_versions do |t|
      # No single-column index: (deck_id, effective_at) below leads with deck_id and serves it.
      t.references :deck, null: false, foreign_key: true, index: false
      t.datetime :effective_at, null: false
      t.string :format, null: false
      t.references :standard_pool, foreign_key: true
      t.string :other_format_name

      t.timestamps
    end
    # A version's number is its rank by (effective_at, id) within its deck, so that is the order
    # every read of this table asks for.
    add_index :deck_versions, [ :deck_id, :effective_at ]

    create_table :deck_version_cards do |t|
      t.references :deck_version, null: false, foreign_key: true, index: false
      t.references :card, null: false, foreign_key: true
      t.integer :quantity, null: false

      t.timestamps

      t.check_constraint "quantity > 0", name: "deck_version_cards_quantity_positive"
    end
    add_index :deck_version_cards, [ :deck_version_id, :card_id ], unique: true

    add_reference :deck_results, :deck_version, foreign_key: true
    add_reference :tournament_entries, :deck_version, foreign_key: true

    backfill

    change_column_null :deck_results, :deck_version_id, false
    change_column_null :tournament_entries, :deck_version_id, false
  end

  def down
    remove_reference :tournament_entries, :deck_version, foreign_key: true
    remove_reference :deck_results, :deck_version, foreign_key: true
    drop_table :deck_version_cards
    drop_table :deck_versions
  end

  # Public so DeckVersionTest can run it against rows it builds in the pre-migration shape: CI
  # loads the schema and never runs a migration, so this is the only place the SQL is exercised.
  #
  # Every deck with at least one result or entry gets version 1 = its current list, and every
  # such result and entry is pointed at it. Only decks and rows with no version yet are touched,
  # and the new versions are told apart from any older ones by id, not by guessing.
  def backfill
    now = connection.quote(Time.current)
    before = connection.select_value("SELECT COALESCE(MAX(id), 0) FROM deck_versions").to_i

    # effective_at is when the current list started: its newest card edit, never earlier than
    # the deck itself. COALESCE comes first because SQLite's two-argument MAX is NULL as soon as
    # either side is, so a deck with results and no card would otherwise abort the NOT NULL.
    execute <<~SQL
      INSERT INTO deck_versions (deck_id, effective_at, format, standard_pool_id, other_format_name, created_at, updated_at)
      SELECT decks.id,
             MAX(COALESCE((SELECT MAX(deck_cards.updated_at) FROM deck_cards WHERE deck_cards.deck_id = decks.id),
                          decks.created_at),
                 decks.created_at),
             decks.format, decks.standard_pool_id, decks.other_format_name, #{now}, #{now}
      FROM decks
      WHERE (EXISTS (SELECT 1 FROM deck_results WHERE deck_results.deck_id = decks.id AND deck_results.deck_version_id IS NULL)
             OR EXISTS (SELECT 1 FROM tournament_entries WHERE tournament_entries.deck_id = decks.id AND tournament_entries.deck_version_id IS NULL))
        AND NOT EXISTS (SELECT 1 FROM deck_versions WHERE deck_versions.deck_id = decks.id)
    SQL

    execute <<~SQL
      INSERT INTO deck_version_cards (deck_version_id, card_id, quantity, created_at, updated_at)
      SELECT deck_versions.id, deck_cards.card_id, deck_cards.quantity, #{now}, #{now}
      FROM deck_cards
      JOIN deck_versions ON deck_versions.deck_id = deck_cards.deck_id
      WHERE deck_versions.id > #{before} AND deck_cards.quantity > 0
    SQL

    %w[deck_results tournament_entries].each do |table|
      execute <<~SQL
        UPDATE #{table}
        SET deck_version_id = (SELECT deck_versions.id FROM deck_versions
                               WHERE deck_versions.deck_id = #{table}.deck_id AND deck_versions.id > #{before})
        WHERE deck_version_id IS NULL
      SQL
    end
  end
end
