class AddTournamentToDeckResults < ActiveRecord::Migration[8.1]
  def change
    add_reference :deck_results, :tournament, foreign_key: true
  end
end
