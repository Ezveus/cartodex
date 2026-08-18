class AddRegionToCardSets < ActiveRecord::Migration[8.1]
  # Every existing row is international by construction: that is the Limitless
  # tree CardSets::Importer scrapes, so the default asserts nothing false.
  #
  # The index widens because Limitless disambiguates its two trees by path, not
  # by code, and codes collide across them (XY7 is a Japanese set; the XY era has
  # international codes too). Kept global, the first Japanese import would die on
  # an incomprehensible uniqueness error. Strictly equivalent while only
  # international sets exist.
  def change
    add_column :card_sets, :region, :string, null: false, default: "international"

    remove_index :card_sets, :code, unique: true
    add_index :card_sets, [ :region, :code ], unique: true
  end
end
