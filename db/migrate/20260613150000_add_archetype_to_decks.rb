class AddArchetypeToDecks < ActiveRecord::Migration[8.1]
  def change
    add_reference :decks, :archetype, null: true, foreign_key: true
  end
end
