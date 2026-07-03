class AddUniqueAllocationIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :deck_cards, [ :deck_id, :card_id ], unique: true
    add_index :collections, [ :user_id, :card_id ], unique: true
  end
end
