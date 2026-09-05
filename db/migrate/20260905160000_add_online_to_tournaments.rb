# An online tournament — one of play.limitlesstcg.com's — is catalogued because a standing needs a
# Tournament (tournament_id is NOT NULL), and hidden from /tournaments because it is not an event
# any member attended. That was the stated objection when this source was first refused, and it is
# about the *catalog*, not about the statistics: one archetype's leaderboard is 20 events, and the
# online index lists 139 archetypes, so left visible these would bury the handful of real events
# members catalogue by hand under a four-figure pile nobody went to.
#
# The index is not decoration. Once this source is imported the table is almost entirely online
# rows, so the catalog's `where(online: false).order(date: :desc)` is a filter that removes ~99 %
# of the table before sorting it — the same reasoning that added index_tournaments_on_tournaments_date
# in the first place, one selective column earlier. That plain date index cannot serve the filter,
# and #index is public, anonymous and rate-limited at 60/min: rationing a request that scans the
# whole table would be rationing an amplifier instead of removing it.
#
# open_participant_count joins the three age-division columns rather than reusing one of them.
# Tournament::DIVISION_COUNT_COLUMNS is what TournamentStanding#placement_within_division_field
# reads, so the "open" division needs its own entry there or a placement of 1 in a field of 259
# is capped against nothing. The online source is the first to publish an attendance at all — all
# three existing columns are nil on every event imported so far.
class AddOnlineToTournaments < ActiveRecord::Migration[8.1]
  def change
    add_column :tournaments, :online, :boolean, null: false, default: false
    add_column :tournaments, :open_participant_count, :integer

    add_index :tournaments, [ :online, :date ]
  end
end
