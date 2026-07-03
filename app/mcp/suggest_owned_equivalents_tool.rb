class SuggestOwnedEquivalentsTool < McpTool
  description "List owned printings physically interchangeable with a given card (same fingerprint) — e.g. reprints and alternate arts — with per-printing owned and available counts. Advisory only."
  input_schema(
    properties: {
      card_id: { type: "integer", description: "ID of the card to find owned equivalents for" }
    },
    required: [ "card_id" ]
  )

  def self.call(card_id:, server_context:)
    user = current_user(server_context)
    card = find_card!(card_id)
    text(Collections::OwnedEquivalents.call(user: user, card: card).to_json)
  rescue ActiveRecord::RecordNotFound
    text("Error: no card with id #{card_id}.")
  end
end
