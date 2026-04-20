class CreateTournamentProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :tournament_profiles do |t|
      t.references :user, null: false, foreign_key: true
      t.string :player_name, null: false
      t.string :player_id, null: false
      t.date :date_of_birth, null: false

      t.timestamps
    end

    add_index :tournament_profiles, :player_id, unique: true
  end
end
