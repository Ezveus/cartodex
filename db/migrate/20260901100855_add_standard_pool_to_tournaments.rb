class AddStandardPoolToTournaments < ActiveRecord::Migration[8.1]
  def change
    add_reference :tournaments, :standard_pool, foreign_key: true
  end
end
