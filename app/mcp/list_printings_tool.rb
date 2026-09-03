class ListPrintingsTool < McpTool
  description "List every printing of a card held in the database (same fingerprint — reprints and alternate arts), owned or not, with per-printing owned and available counts. Given a deck, each entry also reports how many copies that deck already holds and the real/proxy split a swap onto that printing would produce."
  input_schema(
    properties: {
      card_id: { type: "integer", description: "ID of the card whose printings to list" },
      deck_key: { type: "string", description: "Optional: a deck of the user's to annotate the printings for" }
    },
    required: [ "card_id" ]
  )

  def self.call(card_id:, deck_key: nil, server_context:)
    user = current_user(server_context)
    card = find_card!(card_id)
    deck = deck_key && find_deck!(user, deck_key)
    text(Cards::Printings.call(user: user, card: card, deck: deck).to_json)
  rescue ActiveRecord::RecordNotFound
    text("Error: unknown card or deck.")
  end
end
