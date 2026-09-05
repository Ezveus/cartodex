# A bulk standings run writes rows into a public sheet nobody else can clean up afterwards.
# There is no admin tournaments controller; `Tournament has_many :entries,
# dependent: :restrict_with_error` makes an event undeletable the moment one member records a
# participation at it; and an ownerless field list is reachable for deletion through
# TournamentStanding#destroy_ownerless_deck and nothing else, while being listed publicly on
# /decks/shared. So the run has to remember what it created, or a bad import is permanent.
#
# JSON rather than a join table: this is the run's own receipt, read once by the Undo button and
# never joined, aggregated or indexed. `default: []` and NOT NULL together are what let
# Tournaments::StandingsImportUndo subtract from the array without first asking whether it is nil
# — including on the rows every other kind of import writes, which simply never fill it.
class AddCreatedStandingIdsToImports < ActiveRecord::Migration[8.1]
  def change
    change_table :imports do |t|
      t.json :created_standing_ids, null: false, default: []
    end
  end
end
