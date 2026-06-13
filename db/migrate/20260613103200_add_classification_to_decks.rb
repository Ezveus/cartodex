class AddClassificationToDecks < ActiveRecord::Migration[8.1]
  def change
    add_column :decks, :physical, :boolean, default: false, null: false
    add_column :decks, :tcg_live, :boolean, default: false, null: false
    add_column :decks, :format, :string, default: "standard", null: false
    add_column :decks, :other_format_name, :string
    add_column :decks, :has_proxies, :boolean, default: false, null: false
  end
end
