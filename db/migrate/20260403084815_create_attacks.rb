class CreateAttacks < ActiveRecord::Migration[8.0]
  def change
    create_table :attacks do |t|
      t.references :card, null: false, foreign_key: true
      t.string :name
      t.string :cost
      t.string :damage
      t.text :effect
      t.integer :position

      t.timestamps
    end
  end
end
