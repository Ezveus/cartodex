class SetCollectionQuantityTool < McpTool
  description "Set the exact owned quantity of a card in the authenticated user's collection (e.g. to record a sale). May leave physical decks over-allocated; never blocked."
  input_schema(
    properties: {
      card_id: { type: "integer", description: "ID of the card" },
      quantity: { type: "integer", minimum: 0, description: "Exact number of copies owned (0 allowed)" }
    },
    required: [ "card_id", "quantity" ]
  )

  def self.call(card_id:, quantity:, server_context:)
    user = current_user(server_context)
    card = find_card!(card_id)
    collection = Collections::QuantitySetter.call(user: user, card: card, quantity: quantity)
    text("Set #{card.name} owned quantity to #{collection.quantity}.")
  rescue ActiveRecord::RecordNotFound
    text("Error: no card with id #{card_id}.")
  rescue ActiveRecord::RecordInvalid => e
    text("Error: #{e.message}")
  end
end
