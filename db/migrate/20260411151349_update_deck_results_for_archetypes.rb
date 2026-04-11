class UpdateDeckResultsForArchetypes < ActiveRecord::Migration[8.1]
  def change
    add_column :deck_results, :archetype_id, :integer
    add_foreign_key :deck_results, :archetypes
    add_index :deck_results, :archetype_id
    remove_column :deck_results, :opponent_deck_name, :string
  end
end
