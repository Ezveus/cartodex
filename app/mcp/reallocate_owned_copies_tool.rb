class ReallocateOwnedCopiesTool < McpTool
  description "Move real (owned-backed) copies of a card from one physical deck to another. Deck sizes are unchanged; a proxy in the target becomes real and a real in the source becomes a proxy."
  required_scope "mcp:write"
  input_schema(
    properties: {
      from_deck_key: { type: "string", description: "Key of the source physical deck" },
      to_deck_key: { type: "string", description: "Key of the target physical deck" },
      card_id: { type: "integer", description: "ID of the card" },
      quantity: { type: "integer", minimum: 1, description: "How many real copies to move" }
    },
    required: [ "from_deck_key", "to_deck_key", "card_id", "quantity" ]
  )

  def self.call(from_deck_key:, to_deck_key:, card_id:, quantity:, server_context:)
    user = current_user(server_context)
    from_deck = find_deck!(user, from_deck_key)
    to_deck = find_deck!(user, to_deck_key)
    card = find_card!(card_id)
    from, to = Decks::OwnedCopiesReallocator.call(from_deck: from_deck, to_deck: to_deck, card: card, quantity: quantity)
    text("Moved #{quantity}× real #{card.name}: “#{from_deck.name}” now #{from.owned_copies} real, “#{to_deck.name}” now #{to.owned_copies} real.")
  rescue ActiveRecord::RecordNotFound
    text("Error: unknown deck, or the card is not in one of the decks.")
  rescue Decks::OwnedCopiesReallocator::NotPhysicalError
    text("Error: both decks must be physical.")
  rescue ArgumentError => e
    text("Error: #{e.message}")
  end
end
