class AddBrowserOwnershipToSearchSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :search_sessions, :browser_token_digest, :string, limit: 64
    add_index :search_sessions, [:browser_token_digest, :updated_at]
  end
end
