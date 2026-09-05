# An online event is identified by its own Limitless id, not by its name and date.
#
# Tournaments::OnlineResults has always carried the tournament id on every row (Row#event_key) and
# nothing read it: Tournaments::StandingsImportPlan grouped on [event_name, event_date], which is
# the *paper* source's identity rule. Online event names are arbitrary and repeat weekly —
# "Pumpkaweekly", "CrownOfSpain #4" — so two genuinely different tournaments on one day merged into
# a single event, which then took its attendance from whichever row came first and refused the
# other event's rows for a placement above a field size that was never theirs.
#
# So the catalog's own identity rule becomes explicit rather than universal. (name_normalized,
# date) UNIQUE is a statement about the *public catalog* — two members must not catalogue one event
# twice — and was never a claim about the world, so it becomes partial: WHERE online = 0.
# Tournament#name_and_date_are_unique is scoped to match, byte for byte, the way it already is on
# the squish.
#
# What keeps one online event to one row is the second index, and it is partial for the reason
# every partial UNIQUE index in this schema is: SQLite treats NULLs as distinct, so an index over
# the whole column would let every paper event through while claiming to be unique — the trap
# Archetype's old (primary_pokemon_id, secondary_pokemon_id) index fell into, and the reason
# tournament_standings.tournament_entry_id's index carries the same WHERE clause.
class AddExternalKeyToTournaments < ActiveRecord::Migration[8.1]
  def change
    add_column :tournaments, :external_key, :string

    remove_index :tournaments, column: [ :name_normalized, :date ], unique: true,
      name: "index_tournaments_on_name_normalized_and_date"
    add_index :tournaments, [ :name_normalized, :date ], unique: true, where: "online = 0",
      name: "index_tournaments_on_name_normalized_and_date"

    add_index :tournaments, :external_key, unique: true, where: "external_key IS NOT NULL",
      name: "index_tournaments_on_external_key"
  end
end
