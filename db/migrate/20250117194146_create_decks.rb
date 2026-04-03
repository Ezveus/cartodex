class CreateDecks < ActiveRecord::Migration[8.0]
  def change
    create_table :decks do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name
      t.text :description

      t.timestamps
    end
  end
end
