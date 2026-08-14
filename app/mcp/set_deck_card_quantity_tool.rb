class SetDeckCardQuantityTool < McpTool
  description "Set the total number of copies of a card in a deck (proxies included). 0 removes the card. Real copies are recapped to the new total but never auto-increased."
  required_scope "mcp:write"
  input_schema(
    properties: {
      deck_id: { type: "integer", description: "ID of the user's deck" },
      card_id: { type: "integer", description: "ID of the card" },
      quantity: { type: "integer", minimum: 0, description: "New total copies (0 removes the card)" }
    },
    required: [ "deck_id", "card_id", "quantity" ]
  )

  def self.call(deck_id:, card_id:, quantity:, server_context:)
    user = current_user(server_context)
    deck = find_deck!(user, deck_id)
    card = find_card!(card_id)
    deck_card = Decks::DeckCardQuantitySetter.call(deck: deck, card: card, quantity: quantity)
    if deck_card.nil?
      text("Removed #{card.name} from deck “#{deck.name}”.")
    else
      text("#{card.name} in deck “#{deck.name}”: total #{deck_card.quantity} (#{deck_card.owned_copies} real).")
    end
  rescue ActiveRecord::RecordNotFound
    text("Error: unknown deck id #{deck_id} or card id #{card_id} (deck must belong to you).")
  rescue ActiveRecord::RecordInvalid => e
    text("Error: #{e.message}")
  rescue ArgumentError => e
    text("Error: #{e.message}")
  end
end
