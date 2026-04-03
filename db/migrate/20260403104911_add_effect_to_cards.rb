class AddEffectToCards < ActiveRecord::Migration[8.0]
  def change
    add_column :cards, :effect, :text
  end
end
