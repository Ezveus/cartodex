class AddKeyToDecks < ActiveRecord::Migration[8.1]
  def up
    add_column :decks, :key, :string

    # Deliberately not through the model. Deck validates `standard_pool` presence when the
    # format is standard, so `update!` on any pre-#122 Standard row that never got an anchor
    # would abort this migration halfway, leaving a nullable column and no index. Filling a
    # column is all this is; re-validating history is not its job.
    #
    # 16 is spelled out rather than read from Deck::KEY_BYTES: a migration has to keep running
    # after the model has moved on, so it must not depend on a constant the model may rename.
    Deck.reset_column_information
    Deck.where(key: nil).pluck(:id).each do |id|
      Deck.where(id: id).update_all(key: SecureRandom.urlsafe_base64(16))
    end

    change_column_null :decks, :key, false
    add_index :decks, :key, unique: true
  end

  def down
    remove_index :decks, :key
    remove_column :decks, :key
  end
end
