# The online de-duplication key, on the row it identifies.
#
# Tournaments::StandingsImporter's pre-pass groups a run's rows by (player slug, list content) and
# keeps the best finish of each group — which makes the survivors a pure function of *the
# leaderboard*. The database is not a leaderboard. play.limitlesstcg.com publishes a rolling
# top-20, so the survivor a run elected drops off it as twenty better finishes appear, and the next
# run elects a different member of the same group, does not find it, and creates it while the first
# run's row stays:
#
#   run 1  rows W1@4, W2@7, W3@9  -> created 1, duplicates 2   standings [W1]
#   run 2  rows W2@7, W3@9        -> created 1, duplicates 1   standings [W1, W2]
#
# One player, one 60, two lists in the sample — the exact weighting the pre-pass exists to prevent,
# arriving a row at a time. Two smaller doors onto the same accretion, because an in-memory group
# is only ever "this run's rows": an admin splitting a large run with event_filters de-duplicates
# within each filter alone, and a transient decklist fetch failure leaves its row un-keyed and kept,
# so the next healthy run enriches it instead of dropping it.
#
# So the key is stored. Both columns are nullable and both are written by the online importer
# alone: a NULL means "not an online import" and must never participate in de-duplication — the
# paper source publishes no slug, and two paper rows sharing a 60 are two real people who both
# played it.
#
# list_digest is a SHA-256 of the sorted multiset of (set code, number, quantity), which is the
# same key the in-run grouping compares — one method, Tournaments::StandingsImporter.list_digest,
# because two spellings of it would drift and cross-run de-duplication would stop silently.
#
# The index is not decoration: the check is one lookup per run over every standing the archetype
# has, and this table grows by 13 rows per archetype per pool per import.
class AddDedupKeyToTournamentStandings < ActiveRecord::Migration[8.1]
  def change
    add_column :tournament_standings, :player_slug, :string
    add_column :tournament_standings, :list_digest, :string

    add_index :tournament_standings, [ :archetype_id, :player_slug, :list_digest ],
      name: "index_tournament_standings_on_dedup_key"
  end
end
