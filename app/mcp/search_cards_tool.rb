class SearchCardsTool < McpTool
  MAX_LIMIT = 50

  description "Search the card database by name substring, set code and/or collector number (set_number). Give at least one of them. Returns matching cards with their ids."
  input_schema(
    properties: {
      query: { type: "string", description: "Case-insensitive substring of the card name" },
      set_code: { type: "string", description: "Set code to filter by (e.g. \"por\")" },
      set_number: {
        type: [ "string", "integer" ],
        description: "Collector number within the set, matched exactly (e.g. \"86\" or \"GG12\")"
      },
      limit: { type: "integer", description: "Max results (default 20, capped at 50)" }
    },
    required: []
  )

  # Set plus number identifies exactly one printing, so the caller is not required to
  # know the name — but the refusal below tests `blank?` and not `nil?`, because
  # Card.name_matching("") compiles to LIKE '%%' and answers a criterion-less call
  # with the whole catalogue, truncated to `limit`.
  def self.call(server_context:, query: nil, set_code: nil, set_number: nil, limit: 20)
    if query.blank? && set_code.blank? && set_number.blank?
      return text("Error: give at least one of query, set_code or set_number.")
    end

    scope = Card.all
    scope = scope.name_matching(query) if query.present?
    # cards.set_name rather than a join on card_sets: the INNER JOIN hid every card
    # whose set was never imported (44 of them on the production catalogue), the two
    # columns never disagree where both exist, and this is the column CardSearchable
    # already reads — so the two surfaces answer the same question the same way.
    scope = scope.where("UPPER(cards.set_name) = ?", set_code.to_s.upcase) if set_code.present?
    # Matched as text: collector numbers like "GG12" exist and none is zero-padded, so
    # there is no integer to cast to. `.to_s` accepts the integer the schema allows,
    # `.strip` the whitespace a copy-paste carries.
    scope = scope.where(set_number: set_number.to_s.strip) if set_number.present?

    cards = scope.limit(limit.to_i.clamp(1, MAX_LIMIT)).map do |card|
      { id: card.id, name: card.name, set_name: card.set_name, set_number: card.set_number, card_type: card.card_type }
    end
    text(cards.to_json)
  end
end
