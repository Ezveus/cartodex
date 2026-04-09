class AddCardSetToCards < ActiveRecord::Migration[8.1]
  def change
    add_reference :cards, :card_set, foreign_key: true
  end
end
