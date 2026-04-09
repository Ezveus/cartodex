class AddFingerprintToCards < ActiveRecord::Migration[8.1]
  def change
    add_column :cards, :fingerprint, :string
    add_index :cards, [ :name, :fingerprint ]
  end
end
