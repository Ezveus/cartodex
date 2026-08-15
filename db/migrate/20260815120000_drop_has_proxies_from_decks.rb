class DropHasProxiesFromDecks < ActiveRecord::Migration[8.1]
  # The deck-level proxy flag is now derived from the per-card real/proxy split
  # (DeckCard#proxies), so the stored boolean has nothing left to say. No backfill:
  # a physical deck with nothing allocated genuinely holds no real copies.
  def change
    remove_column :decks, :has_proxies, :boolean, default: false, null: false
  end
end
