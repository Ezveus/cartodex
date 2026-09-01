class CreateStandardPools < ActiveRecord::Migration[8.1]
  def change
    create_table :standard_pools do |t|
      t.references :first_card_set, null: false, foreign_key: { to_table: :card_sets }
      t.references :last_card_set,  null: false, foreign_key: { to_table: :card_sets }
      t.json :regulation_marks, null: false
      t.date :released_on, null: false
      t.date :legal_on, null: false

      t.timestamps
    end

    # The bound pair is the pool's name ("TEF-PBL"); two rows must not claim it.
    add_index :standard_pools, [ :first_card_set_id, :last_card_set_id ],
      unique: true, name: "index_standard_pools_on_bounds"
  end
end
