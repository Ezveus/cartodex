class CreateImports < ActiveRecord::Migration[8.1]
  def change
    create_table :imports do |t|
      t.string :kind, null: false
      t.string :status, null: false, default: "pending"
      t.string :label, null: false
      t.text :error_message
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end

    add_index :imports, [ :user_id, :status ]
    add_index :imports, [ :kind, :status ]
  end
end
