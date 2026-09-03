class SplitTournamentsIntoEventsAndEntries < ActiveRecord::Migration[8.1]
  # Isolated from the app models on purpose, the same way
  # AddNameNormalizedToDeckTournamentArchetype is: this backfill must keep working whatever
  # those classes grow into, and during this migration neither of them matches its table.
  class MigrationTournament < ActiveRecord::Base
    self.table_name = "tournaments"
  end

  class MigrationEntry < ActiveRecord::Base
    self.table_name = "tournament_entries"
  end

  EVENT_COLUMNS = %w[name name_normalized date tier format other_format_name standard_pool_id].freeze

  def up
    check_for_colliding_entries!

    # The old table *is* the participation: deck_results.tournament_id already points at it,
    # so renaming the table and renaming that column rewrites no row in deck_results at all.
    rename_table :tournaments, :tournament_entries
    rename_column :deck_results, :tournament_id, :tournament_entry_id

    create_table :tournaments do |t|
      t.string :name, null: false
      # NOT NULL although the column it comes from is nullable: NameNormalizable maintains it
      # in a callback and the UNIQUE index below depends on it. The backfill re-derives it for
      # any legacy row that somehow has none.
      t.string :name_normalized, null: false
      t.date :date, null: false
      t.string :tier, null: false, default: "regional"
      t.string :format, null: false, default: "standard"
      t.string :other_format_name
      t.references :standard_pool, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }

      t.timestamps
    end
    # This pair *is* the event's name: "2026 Los Angeles Regional" on 2026-03-14 is one
    # tournament however many members attended it.
    add_index :tournaments, [ :name_normalized, :date ], unique: true

    add_reference :tournament_entries, :tournament, foreign_key: true

    backfill_events

    change_column_null :tournament_entries, :tournament_id, false
    EVENT_COLUMNS.each { |column| remove_column :tournament_entries, column }

    # Two partial indexes rather than one, because SQLite treats NULLs as distinct: a single
    # index on (tournament_id, tournament_profile_id) would let a member record the same
    # profile-less event twice, which is the bug Archetype's old index had for as long as it
    # existed. A profile belongs to exactly one user, so the first index implies the user too.
    add_index :tournament_entries, [ :tournament_id, :tournament_profile_id ],
      unique: true, where: "tournament_profile_id IS NOT NULL",
      name: "index_tournament_entries_on_tournament_and_profile"
    add_index :tournament_entries, [ :tournament_id, :user_id ],
      unique: true, where: "tournament_profile_id IS NULL",
      name: "index_tournament_entries_on_tournament_and_user"
  end

  def down
    remove_index :tournament_entries, name: "index_tournament_entries_on_tournament_and_user"
    remove_index :tournament_entries, name: "index_tournament_entries_on_tournament_and_profile"

    add_column :tournament_entries, :name, :string
    add_column :tournament_entries, :name_normalized, :string
    add_column :tournament_entries, :date, :date
    add_column :tournament_entries, :tier, :string, default: "regional"
    add_column :tournament_entries, :format, :string, default: "standard"
    add_column :tournament_entries, :other_format_name, :string
    add_reference :tournament_entries, :standard_pool, foreign_key: true

    restore_event_columns

    change_column_null :tournament_entries, :name, false
    change_column_null :tournament_entries, :date, false
    change_column_null :tournament_entries, :tier, false
    change_column_null :tournament_entries, :format, false

    remove_reference :tournament_entries, :tournament, foreign_key: true
    drop_table :tournaments
    rename_column :deck_results, :tournament_entry_id, :tournament_id
    rename_table :tournament_entries, :tournaments
  end

  private

  # The one expression that decides which rows become one event. Shared with the pre-flight on
  # purpose: when the guard grouped in SQL and the backfill coalesced in Ruby, a row whose
  # name_normalized was NULL slipped past the guard and then collided on the unique index — as a
  # raw constraint error instead of the crafted message.
  def merge_key_name(normalized, name)
    normalized.presence || name.to_s.downcase
  end

  # Runs before anything is mutated, so the migration is replayable after a human has decided
  # what the offending rows mean. Two rows that agree on (user, profile, merged name, date)
  # would merge into one event and then violate the entry uniqueness index — and this migration
  # never deletes a row of its own accord. Grouped in Ruby, on the same merge_key_name the
  # backfill uses, rather than in SQL: SQLite's LOWER() folds ASCII A-Z only, so a SQL-side
  # COALESCE(NULLIF(name_normalized, ''), LOWER(name)) would still disagree with Ruby's
  # Unicode-aware downcase on an accented name — the whole reason name_normalized exists.
  def check_for_colliding_entries!
    rows = select_all(<<~SQL).to_a
      SELECT id, user_id, tournament_profile_id, name, name_normalized, date
      FROM tournaments
    SQL

    groups = rows.group_by do |row|
      [ row["user_id"], row["tournament_profile_id"], merge_key_name(row["name_normalized"], row["name"]), row["date"] ]
    end
    colliding = groups.select { |_key, group_rows| group_rows.size > 1 }
    return if colliding.empty?

    details = colliding.map do |(user_id, profile_id, merged_name, date), group_rows|
      ids = group_rows.map { |row| row["id"] }.join(",")
      "  ids #{ids} — user #{user_id}, profile #{profile_id.inspect}, #{merged_name.inspect} on #{date}"
    end

    raise <<~MESSAGE
      Refusing to split: these tournament rows would merge into one event and then collide on
      the per-player uniqueness index. Nothing has been changed. Decide what each group means
      (keep one, rename one, or move one to its real date) and re-run.

      #{details.join("\n")}
    MESSAGE
  end

  def backfill_events
    MigrationTournament.reset_column_information
    MigrationEntry.reset_column_information

    # Ascending id, so the oldest participation is the one whose values the event keeps and
    # whose owner becomes its creator.
    MigrationEntry.order(:id).each do |entry|
      normalized = merge_key_name(entry.name_normalized, entry.name)
      event = MigrationTournament.find_or_create_by!(name_normalized: normalized, date: entry.date) do |t|
        t.name = entry.name
        t.tier = entry.tier
        t.format = entry.format
        t.other_format_name = entry.other_format_name
        t.standard_pool_id = entry.standard_pool_id
        t.created_by_id = entry.user_id
      end
      entry.update_column(:tournament_id, event.id)
    end
  end

  def restore_event_columns
    MigrationTournament.reset_column_information
    MigrationEntry.reset_column_information
    events = MigrationTournament.all.index_by(&:id)

    MigrationEntry.find_each do |entry|
      event = events[entry.tournament_id]
      entry.update_columns(
        name: event.name, name_normalized: event.name_normalized, date: event.date,
        tier: event.tier, format: event.format, other_format_name: event.other_format_name,
        standard_pool_id: event.standard_pool_id
      )
    end
  end
end
