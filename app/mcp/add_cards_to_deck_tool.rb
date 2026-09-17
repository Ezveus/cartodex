class AddCardsToDeckTool < McpTool
  extend BulkAdd

  description "Add many printings to one of the user's decks in one call, each named by its set code and " \
              "collector number rather than by a card id — that pair is unique, so no lookup is needed " \
              "first. Repeat an entry instead of counting; the server sums the repeats. On a physical deck " \
              "each row is backed by as many owned copies as the collection leaves free, the rest being " \
              "proxies. If any entry cannot be resolved the whole call is refused and nothing is written."
  required_scope "mcp:write"
  input_schema(
    properties: {
      deck_key: { type: "string", description: "Key of the user's deck" },
      entries: entries_schema("The printings to add, in the order they were listed. Repeats are summed.")
    },
    required: [ "deck_key", "entries" ]
  )

  def self.call(deck_key:, entries:, server_context:)
    refusal = entries_refusal(entries)
    return refusal if refusal

    user = current_user(server_context)
    deck = find_deck!(user, deck_key)
    resolution = Cards::ReferenceResolver.call(entries: entries)
    refusal = unresolved_refusal(resolution.unresolved)
    return refusal if refusal

    label = nil
    receipt = ActiveRecord::Base.transaction do
      written = Decks::BulkCardAdder.call(deck: deck, resolved: resolution.resolved)
      label = summary_label("Deck “#{deck.name}”", written)
      record_import(user: user, label: label, receipt: written)
      written
    end

    success_text(label, receipt)
  rescue ActiveRecord::StatementTimeout, ActiveRecord::LockWaitTimeout
    error_text(
      "Error: the database was busy and nothing was written. SQLite has a single write lock and " \
      "another write held it for longer than the 5 s timeout. Sending the same list again is safe " \
      "\u2014 the lock is taken before the first row, so a call that waited it out wrote nothing."
    )
  rescue ActiveRecord::RecordNotFound
    error_text("Error: unknown deck key #{deck_key.inspect} (the deck must belong to you).")
  rescue ActiveRecord::RecordInvalid => e
    error_text("Error: #{e.message}")
  end
end
