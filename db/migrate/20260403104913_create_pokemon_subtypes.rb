class CreatePokemonSubtypes < ActiveRecord::Migration[8.0]
  def change
    create_table :pokemon_subtypes do |t|
      t.string :name
      t.boolean :rule_box
      t.integer :prize_cards_on_ko
      t.text :rule_text

      t.timestamps
    end
  end
end
