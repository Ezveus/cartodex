class CreateCollections < ActiveRecord::Migration[8.0]
  def change
    create_table :collections do |t|
      t.references :user, null: false, foreign_key: true
      t.references :card, null: false, foreign_key: true
      t.integer :quantity
      t.boolean :foil

      t.timestamps
    end
  end
end
