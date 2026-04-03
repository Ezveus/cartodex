class CreateCards < ActiveRecord::Migration[8.0]
  def change
    create_table :cards do |t|
      t.string :name
      t.string :card_type
      t.string :subtype
      t.string :set_name
      t.string :set_number
      t.string :rarity
      t.string :image_url
      t.integer :hp
      t.string :stage
      t.string :type_symbol
      t.integer :retreat_cost
      t.string :artist

      t.timestamps
    end
  end
end
