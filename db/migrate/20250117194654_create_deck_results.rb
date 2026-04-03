class CreateDeckResults < ActiveRecord::Migration[8.0]
  def change
    create_table :deck_results do |t|
      t.references :deck, null: false, foreign_key: true
      t.string :result
      t.string :opponent_deck_name
      t.text :notes
      t.datetime :played_at

      t.timestamps
    end
  end
end
