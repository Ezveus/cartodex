class AddCardToCollectionTool < McpTool
  description "Add a quantity of a card (by card_id) to the authenticated user's collection."
  input_schema(
    properties: {
      card_id: { type: "integer", description: "ID of the card to add" },
      quantity: { type: "integer", minimum: 1, description: "How many copies to add (default 1)" }
    },
    required: [ "card_id" ]
  )

  def self.call(card_id:, server_context:, quantity: 1)
    return quantity_error(quantity) unless positive_quantity?(quantity)

    user = current_user(server_context)
    card = find_card!(card_id)
    collection = Collections::CardAdder.call(user: user, card: card, quantity: quantity)
    text("Added #{quantity}× #{card.name} to your collection (now #{collection.quantity}).")
  rescue ActiveRecord::RecordNotFound
    text("Error: no card with id #{card_id}.")
  rescue ActiveRecord::RecordInvalid => e
    text("Error: #{e.message}")
  end
end
