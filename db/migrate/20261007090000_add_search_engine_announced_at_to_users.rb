# When the member was shown the "use Cartodex as a search engine" announcement. Nil is "not yet",
# which is every member at deploy time and every account created afterwards — see
# docs/superpowers/specs/2026-10-07-browser-search-engine-design.md.
class AddSearchEngineAnnouncedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :search_engine_announced_at, :datetime
  end
end
