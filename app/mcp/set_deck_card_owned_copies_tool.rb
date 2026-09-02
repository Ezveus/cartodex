class SetDeckCardOwnedCopiesTool < McpTool
  description "Set how many copies of a card in a physical deck are backed by owned cards (the rest are proxies). Bounded by the deck total and by availability; cannot create over-allocation."
  required_scope "mcp:write"
  input_schema(
    properties: {
      deck_key: { type: "string", description: "Key of the user's physical deck" },
      card_id: { type: "integer", description: "ID of the card" },
      owned_copies: { type: "integer", minimum: 0, description: "Number of real (owned-backed) copies" }
    },
    required: [ "deck_key", "card_id", "owned_copies" ]
  )

  def self.call(deck_key:, card_id:, owned_copies:, server_context:)
    user = current_user(server_context)
    deck = find_deck!(user, deck_key)
    card = find_card!(card_id)
    deck_card = Decks::OwnedCopiesSetter.call(deck: deck, card: card, owned_copies: owned_copies)
    text("#{card.name} in deck “#{deck.name}”: #{deck_card.owned_copies} real, #{deck_card.quantity - deck_card.owned_copies} proxy.")
  rescue ActiveRecord::RecordNotFound
    text("Error: unknown deck, or the card is not in that deck.")
  rescue Decks::OwnedCopiesSetter::NotPhysicalError
    text("Error: deck “#{deck&.name}” is not physical; only physical decks back owned copies.")
  rescue ArgumentError => e
    text("Error: #{e.message}")
  end
end
