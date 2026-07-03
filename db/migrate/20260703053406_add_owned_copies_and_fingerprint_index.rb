class AddOwnedCopiesAndFingerprintIndex < ActiveRecord::Migration[8.1]
  def change
    add_column :deck_cards, :owned_copies, :integer, default: 0, null: false
    add_index :cards, :fingerprint
  end
end
