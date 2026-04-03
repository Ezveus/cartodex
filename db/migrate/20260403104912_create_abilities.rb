class CreateAbilities < ActiveRecord::Migration[8.0]
  def change
    create_table :abilities do |t|
      t.references :card, null: false, foreign_key: true
      t.string :name
      t.text :effect
      t.integer :position

      t.timestamps
    end
  end
end
