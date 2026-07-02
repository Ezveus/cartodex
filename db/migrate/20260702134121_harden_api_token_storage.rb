class HardenApiTokenStorage < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :api_token_digest, :string
    add_index :users, :api_token_digest, unique: true

    User.reset_column_information
    User.find_each do |user|
      user.update_columns(api_token_digest: User.digest_api_token(User.generate_api_token))
    end

    remove_index :users, :api_token
    remove_column :users, :api_token
  end

  def down
    add_column :users, :api_token, :string
    add_index :users, :api_token, unique: true

    remove_index :users, :api_token_digest
    remove_column :users, :api_token_digest
  end
end
