# Three parts, one migration — and the third is why the other two cannot ship without it. Making
# decks.user_id nullable turns three `deck.user.email` reads in the admin panel from dead code
# into NoMethodErrors and two more reads into wrong answers, so the audit fixes ship in this
# same commit.
class CreateTournamentStandings < ActiveRecord::Migration[8.1]
  def change
    create_table :tournament_standings do |t|
      t.references :tournament, null: false, foreign_key: true
      t.string :player_name, null: false
      # NOT NULL although the model maintains it in a callback, for the reason
      # tournaments.name_normalized is: the UNIQUE index below depends on it.
      t.string :player_name_normalized, null: false
      t.string :division, null: false
      t.integer :placement
      t.integer :wins
      t.integer :losses
      t.integer :ties
      # NOT NULL: the archetype is the point of the record. A row that names nobody's deck
      # archetype records nothing a metagame reader can use.
      t.references :archetype, null: false, foreign_key: true
      # The event's field list — a Deck owned by nobody. Optional: most rows name an archetype
      # and no list.
      t.references :deck, foreign_key: true
      # index: false because the partial UNIQUE index below covers this column on its own, and a
      # second plain index on the same single column would be pure duplication.
      t.references :tournament_entry, foreign_key: true, index: false
      t.references :created_by, foreign_key: { to_table: :users }

      t.timestamps
    end

    # One player, one row per division. The model validation exists for the readable error, this
    # index for the guarantee — the same division of labour as (set_name, set_number) on Card and
    # (name_normalized, date) on Tournament.
    add_index :tournament_standings, [ :tournament_id, :player_name_normalized, :division ],
      unique: true, name: "index_tournament_standings_on_event_and_player"
    # The sheet's own sort. The null-last expression the scope adds is computed, so this index
    # serves the (tournament_id, division) prefix rather than the whole ORDER BY.
    add_index :tournament_standings, [ :tournament_id, :division, :placement ],
      name: "index_tournament_standings_on_event_division_placement"
    # A participation is published at most once. This is the index that actually stops a member
    # publishing themselves twice under two spellings of their own name, which the name key
    # cannot see. Partial, because SQLite treats NULLs as distinct and every unclaimed row
    # carries one — the trap Archetype's old index fell into.
    add_index :tournament_standings, :tournament_entry_id, unique: true,
      where: "tournament_entry_id IS NOT NULL",
      name: "index_tournament_standings_on_claimed_entry"

    # Per-division field sizes, on the event rather than on each row: two players in the same
    # division at the same event are ranked against the same number.
    add_column :tournaments, :junior_participant_count, :integer
    add_column :tournaments, :senior_participant_count, :integer
    add_column :tournaments, :masters_participant_count, :integer

    # A tournament field list belongs to an event, not to a member. No backfill: every existing
    # deck keeps its owner.
    change_column_null :decks, :user_id, true
  end
end
