class CreateTournaments < ActiveRecord::Migration[8.1]
  def change
    create_table :tournaments do |t|
      t.references :user, null: false, foreign_key: true
      t.references :deck, null: false, foreign_key: true
      t.references :tournament_profile, foreign_key: true
      t.string :name, null: false
      t.date :date, null: false
      t.string :format, null: false, default: "standard"
      t.string :other_format_name
      t.string :tier, null: false, default: "regional"
      t.integer :participant_count
      t.integer :placement
      t.integer :championship_points

      t.timestamps
    end
  end
end
