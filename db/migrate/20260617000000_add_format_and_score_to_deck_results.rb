class AddFormatAndScoreToDeckResults < ActiveRecord::Migration[8.1]
  def change
    add_column :deck_results, :match_format, :string, null: false, default: "bo1"
    add_column :deck_results, :score, :string
  end
end
