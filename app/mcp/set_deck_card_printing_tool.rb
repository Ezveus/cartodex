class SetDeckCardPrintingTool < McpTool
  description "Switch a deck slot from one printing of a card to another (same card, different set and number), keeping its quantity. Merges with an existing row for the target printing, and re-derives the real/proxy split against what the target printing leaves available — a swap onto a printing you do not own turns real copies into proxies."
  required_scope "mcp:write"
  input_schema(
    properties: {
      deck_id: { type: "integer", description: "ID of the user's deck" },
      card_id: { type: "integer", description: "ID of the printing currently in the deck" },
      target_card_id: { type: "integer", description: "ID of the printing to switch to" }
    },
    required: [ "deck_id", "card_id", "target_card_id" ]
  )

  def self.call(deck_id:, card_id:, target_card_id:, server_context:)
    user = current_user(server_context)
    deck = find_deck!(user, deck_id)
    card = find_card!(card_id)
    target = find_card!(target_card_id)
    deck_card = Decks::PrintingSwapper.call(deck: deck, card: card, target_card: target)

    text("#{target.name} in deck “#{deck.name}” is now #{target.set_name} #{target.set_number}: " \
         "#{deck_card.quantity} copies, #{deck_card.owned_copies} real, #{deck_card.proxies} proxy.")
  rescue ActiveRecord::RecordNotFound
    text("Error: unknown deck or card, or the card is not in that deck.")
  rescue ArgumentError => e
    text("Error: #{e.message}")
  end
end
