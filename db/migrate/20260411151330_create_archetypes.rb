class CreateArchetypes < ActiveRecord::Migration[8.1]
  def change
    create_table :archetypes do |t|
      t.string :name, null: false
      t.integer :primary_pokemon_id, null: false
      t.integer :secondary_pokemon_id
      t.integer :parent_id

      t.timestamps
    end

    add_foreign_key :archetypes, :cards, column: :primary_pokemon_id
    add_foreign_key :archetypes, :cards, column: :secondary_pokemon_id
    add_foreign_key :archetypes, :archetypes, column: :parent_id
    add_index :archetypes, [ :primary_pokemon_id, :secondary_pokemon_id ], unique: true
    add_index :archetypes, :parent_id
  end
end
