class RenameArchetypePokemonColumns < ActiveRecord::Migration[8.1]
  # An archetype's members were always Cards; only the column names claimed they
  # were Pokémon. The index is dropped and re-added by hand rather than left to
  # `rename_column`, which regenerates the auto-derived name — the next migration
  # has to remove this index, and it can only do that if it knows what it is called.
  def up
    remove_index :archetypes, name: "idx_on_primary_pokemon_id_secondary_pokemon_id_2a04cf9ccd"
    rename_column :archetypes, :primary_pokemon_id, :primary_card_id
    rename_column :archetypes, :secondary_pokemon_id, :secondary_card_id
    add_index :archetypes, [ :primary_card_id, :secondary_card_id ],
      unique: true, name: "index_archetypes_on_card_pair"
  end

  def down
    remove_index :archetypes, name: "index_archetypes_on_card_pair"
    rename_column :archetypes, :primary_card_id, :primary_pokemon_id
    rename_column :archetypes, :secondary_card_id, :secondary_pokemon_id
    add_index :archetypes, [ :primary_pokemon_id, :secondary_pokemon_id ],
      unique: true, name: "idx_on_primary_pokemon_id_secondary_pokemon_id_2a04cf9ccd"
  end
end
