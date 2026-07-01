class MoveCardToDeckTool < McpTool
  description "Move a quantity of a card from the collection into a deck (collection down, deck up)."
  input_schema(
    properties: {
      deck_id: { type: "integer", description: "ID of the user's deck" },
      card_id: { type: "integer", description: "ID of the card to move" },
      quantity: { type: "integer", description: "How many copies to move (default 1)" }
    },
    required: [ "deck_id", "card_id" ]
  )

  def self.call(deck_id:, card_id:, server_context:, quantity: 1)
    user = current_user(server_context)
    deck = find_deck!(user, deck_id)
    card = find_card!(card_id)
    result = Decks::CardTransfer.call(user: user, deck: deck, card: card, direction: :in, quantity: quantity)
    text("Moved #{quantity}× #{card.name} into deck “#{deck.name}”. " \
         "Collection: #{result.collection_quantity}, deck: #{result.deck_quantity}.")
  rescue ActiveRecord::RecordNotFound
    text("Error: unknown deck id #{deck_id} or card id #{card_id} (deck must belong to you).")
  end
end
