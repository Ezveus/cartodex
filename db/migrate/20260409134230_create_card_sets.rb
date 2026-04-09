class CreateCardSets < ActiveRecord::Migration[8.1]
  def change
    create_table :card_sets do |t|
      t.string :code
      t.string :name
      t.string :logo_url
      t.date :release_date
      t.string :block_name

      t.timestamps
    end
    add_index :card_sets, :code, unique: true
  end
end
