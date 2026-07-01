class AddApiTokenToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :api_token, :string
    add_index :users, :api_token, unique: true

    User.reset_column_information
    User.where(api_token: nil).find_each do |user|
      user.update_columns(api_token: SecureRandom.base58(24))
    end
  end

  def down
    remove_index :users, :api_token
    remove_column :users, :api_token
  end
end
