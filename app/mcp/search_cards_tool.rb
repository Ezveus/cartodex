class SearchCardsTool < McpTool
  MAX_LIMIT = 50

  description "Search the card database by name substring (optionally filtered by set code). Returns matching cards with their ids."
  input_schema(
    properties: {
      query: { type: "string", description: "Case-insensitive substring of the card name" },
      set_code: { type: "string", description: "Optional set code to filter by (e.g. \"por\")" },
      limit: { type: "integer", description: "Max results (default 20, capped at 50)" }
    },
    required: [ "query" ]
  )

  def self.call(query:, server_context:, set_code: nil, limit: 20)
    scope = Card.name_matching(query)
    scope = scope.joins(:card_set).where("LOWER(card_sets.code) = ?", set_code.downcase) if set_code.present?
    cards = scope.limit(limit.to_i.clamp(1, MAX_LIMIT)).map do |card|
      { id: card.id, name: card.name, set_name: card.set_name, set_number: card.set_number, card_type: card.card_type }
    end
    text(cards.to_json)
  end
end
