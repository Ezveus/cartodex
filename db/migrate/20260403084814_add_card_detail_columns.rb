class AddCardDetailColumns < ActiveRecord::Migration[8.0]
  def change
    change_table :cards do |t|
      t.string :weakness
      t.string :resistance
      t.string :evolves_from
      t.string :regulation_mark
      t.string :set_full_name
      t.decimal :price_usd, precision: 8, scale: 2
      t.decimal :price_eur, precision: 8, scale: 2
    end
  end
end
