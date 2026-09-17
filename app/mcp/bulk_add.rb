# Shared by AddCardsToCollectionTool and AddCardsToDeckTool: the entry schema, the four refusals,
# and the Import row both of them write.
#
# A module extended into each tool rather than a common superclass, because `McpTool.descendants`
# is what the registration test reads — an abstract subclass sitting between the two would be a
# descendant nothing registers, and the test would have to grow an exception exactly where it is
# supposed to be exhaustive.
module BulkAdd
  # Sized on how long the write transaction holds SQLite's single write lock, not on how many bind
  # variables fit. Measured on the real catalogue: 50 entries hold it 0.21 s, 100 hold it 0.31 s,
  # 250 hold it 0.80 s and 500 hold it 1.2-4.0 s — and four concurrent 500-entry calls exhaust
  # database.yml's `timeout: 5000`, while a member clicking `+` on a card page waited 2.98 s behind
  # six of them. 120 is ~0.35 s and still twice the largest real payload (a booster box measured 58
  # distinct printings; a Commander deck is 100). Beyond it the caller sends two calls, each atomic
  # on its own.
  #
  # No cap makes the lock un-monopolisable: the per-user MCP quota is 300 calls/min, so even at 120
  # a member who wants to can ask for more lock time than a minute contains. What the cap buys is
  # that an *ordinary* run cannot do it by accident.
  MAX_ENTRIES = 120

  ENTRY = {
    type: "object",
    properties: {
      set_code: { type: "string", description: "Set code, matched case-insensitively (e.g. \"PBL\")" },
      # Declared as both, for the reason SearchCardsTool records: `mcp` enforces the declared schema
      # on the wire, and an assistant reading "56" off a card sends the integer as often as the
      # string. Matched as text either way — 100 printings carry GG1-style numbers.
      set_number: { type: [ "string", "integer" ], description: "Collector number, matched exactly as text (e.g. \"56\" or \"GG1\")" },
      quantity: { type: "integer", minimum: 1, description: "Copies of this printing (default 1). Repeating the entry instead is equally valid, and preferred: the server sums the repeats" }
    },
    required: [ "set_code", "set_number" ]
  }.freeze

  def entries_schema(description)
    { type: "array", minItems: 1, maxItems: MAX_ENTRIES, items: ENTRY, description: description }
  end

  # Returns a refusal Response, or nil when the shape is acceptable. The JSON schema already
  # rejects these on a real MCP call; an in-process call bypasses it entirely, which is what
  # McpTool#positive_quantity? exists for and the same reason these are checked again here.
  def entries_refusal(entries)
    # `all?(Hash)` and not merely "is an Array": an item that is a String or an Array answers `[]`
    # with an Integer index, so ReferenceResolver#read raises an unrescued TypeError rather than
    # refusing. The wire schema already requires objects here; this is the in-process door, the
    # same one McpTool#positive_quantity? exists to cover.
    unless entries.is_a?(Array) && entries.any? && entries.all?(Hash)
      return error_text("Error: entries must be a non-empty array of { set_code, set_number, quantity? } objects.")
    end
    return unless entries.size > MAX_ENTRIES

    error_text("Error: at most #{MAX_ENTRIES} entries per call (got #{entries.size}).")
  end

  # All or nothing: one unresolved entry refuses the whole call and writes nothing, so a caller
  # that fixes the typo and resends the same list adds each copy exactly once. Applying the rest
  # and reporting the failures would be friendlier and would resurrect the hazard this design
  # exists to remove — these adds are relative, and a resent message would add the others twice.
  def unresolved_refusal(unresolved)
    return if unresolved.empty?

    lines = unresolved.map { |entry| "  #{reference_label(entry)} — #{entry[:reason]}" }
    error_text(
      "Error: #{unresolved.size} #{'entry'.pluralize(unresolved.size)} could not be resolved, " \
      "nothing was written:\n#{lines.join("\n")}"
    )
  end

  # Names both counts, always, and they are two different numbers: 58 copies over 52 printings is
  # what one booster box looked like.
  def summary_label(target, receipt)
    copies = receipt.sum { |entry| entry["quantity"] }
    "#{target} — #{copies} #{'copy'.pluralize(copies)} over #{receipt.size} #{'printing'.pluralize(receipt.size)}"
  end

  # The response is built from the receipt rather than from what the caller asked for: it is a
  # reading of the resulting state, which is the reconciliation a per-card run could never afford.
  def success_text(label, receipt)
    lines = receipt.map do |entry|
      line = "  #{entry['name']} (#{entry['set_name']} #{entry['set_number']}) ×#{entry['quantity']} — #{entry['before']} → #{entry['after']}"
      line += " (#{entry['owned_before']} → #{entry['owned_after']} real)" if entry.key?("owned_after")
      line
    end
    text("#{label}.\n#{lines.join("\n")}")
  end

  # 9223372036854775807 passes the schema's `type: "integer"` and then overflows the column, which
  # ActiveModel raises as a RangeError that no rescue caught — the client got a bare JSON-RPC
  # internal error with no isError. (The pre-existing per-card tools still do; that is theirs.)
  def out_of_range_refusal
    error_text("Error: a quantity is larger than the database can hold. Nothing was written.")
  end

  def record_import(user:, label:, receipt:)
    user.imports.create!(kind: "bulk_cards", status: "completed", label: label, receipt: receipt)
  end

  private

  def reference_label(entry)
    [ entry[:set_code], entry[:set_number] ].reject { |part| part.to_s.empty? }.join(" ").presence || "(blank entry)"
  end
end
