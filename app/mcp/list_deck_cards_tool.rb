class ListDeckCardsTool < McpTool
  description "List the cards in one of the user's decks with their ids and quantities."
  input_schema(
    properties: {
      deck_id: { type: "integer", description: "ID of the user's deck" }
    },
    required: [ "deck_id" ]
  )

  def self.call(deck_id:, server_context:)
    user = current_user(server_context)
    deck = find_deck!(user, deck_id)
    entries = deck.deck_cards.includes(:card).map do |deck_card|
      {
        card_id: deck_card.card_id,
        name: deck_card.card.name,
        quantity: deck_card.quantity,
        owned_copies: deck_card.owned_copies,
        proxies: deck_card.quantity - deck_card.owned_copies
      }
    end
    text(entries.to_json)
  rescue ActiveRecord::RecordNotFound
    text("Error: unknown deck id #{deck_id} (deck must belong to you).")
  end
end
