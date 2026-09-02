class AddCardToDeckTool < McpTool
  description "Add (link) a quantity of a card to one of the user's decks, without changing the collection."
  required_scope "mcp:write"
  input_schema(
    properties: {
      deck_key: { type: "string", description: "Key of the user's deck" },
      card_id: { type: "integer", description: "ID of the card to add" },
      quantity: { type: "integer", minimum: 1, description: "How many copies to add (default 1)" }
    },
    required: [ "deck_key", "card_id" ]
  )

  def self.call(deck_key:, card_id:, server_context:, quantity: 1)
    return quantity_error(quantity) unless positive_quantity?(quantity)

    user = current_user(server_context)
    deck = find_deck!(user, deck_key)
    card = find_card!(card_id)
    deck_card = Decks::CardAdder.call(deck: deck, card: card, quantity: quantity)
    message = "Added #{quantity}× #{card.name} to deck “#{deck.name}” (now #{deck_card.quantity}: #{deck_card.owned_copies} real, #{deck_card.quantity - deck_card.owned_copies} proxy)."
    message += equivalents_hint(user, card) if deck.physical? && deck_card.quantity > deck_card.owned_copies
    text(message)
  rescue ActiveRecord::RecordNotFound
    text("Error: unknown deck key #{deck_key.inspect} or card id #{card_id} (deck must belong to you).")
  rescue ActiveRecord::RecordInvalid => e
    text("Error: #{e.message}")
  end

  def self.equivalents_hint(user, card)
    equivalents = Collections::OwnedEquivalents.call(user: user, card: card, excluding_card: true)
    return "" if equivalents.empty?

    " You own equivalent printings you could back real copies with instead: #{equivalents.to_json}"
  end
  private_class_method :equivalents_hint
end
