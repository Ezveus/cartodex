class AddApiTokenMetadataToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :api_token_created_at, :datetime
    add_column :users, :api_token_expires_at, :datetime
    add_column :users, :api_token_last_used_at, :datetime
  end
end
