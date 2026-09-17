class AddCardsToCollectionTool < McpTool
  extend BulkAdd

  description "Add many printings to the authenticated user's collection in one call, each named by " \
              "its set code and collector number rather than by a card id — that pair is unique, so no " \
              "lookup is needed first. Repeat an entry instead of counting: \"PBL 56, 56\" is two entries, " \
              "and the server sums them. If any entry cannot be resolved the whole call is refused and " \
              "nothing is written, so fixing it and resending the same list is safe."
  required_scope "mcp:write"
  input_schema(
    properties: {
      entries: entries_schema("The printings to add, in the order they were listed. Repeats are summed.")
    },
    required: [ "entries" ]
  )

  def self.call(entries:, server_context:)
    refusal = entries_refusal(entries)
    return refusal if refusal

    user = current_user(server_context)
    resolution = Cards::ReferenceResolver.call(entries: entries)
    refusal = unresolved_refusal(resolution.unresolved)
    return refusal if refusal

    # The receipt and the Import row commit together with the cards: an Import that named copies
    # nobody has, or copies with no Import naming them, are both worse than neither.
    label = nil
    receipt = ActiveRecord::Base.transaction do
      written = Collections::BulkCardAdder.call(user: user, resolved: resolution.resolved)
      label = summary_label("Collection", written)
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
  rescue ActiveRecord::RecordInvalid => e
    error_text("Error: #{e.message}")
  end
end
