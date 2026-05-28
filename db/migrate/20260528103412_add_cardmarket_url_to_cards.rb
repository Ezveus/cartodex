class AddCardmarketUrlToCards < ActiveRecord::Migration[8.1]
  def change
    add_column :cards, :cardmarket_url, :string
  end
end
