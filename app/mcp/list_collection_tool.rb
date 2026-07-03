class ListCollectionTool < McpTool
  description "List the authenticated user's collection (cards with quantity > 0), optionally filtered by card name."
  input_schema(
    properties: {
      query: { type: "string", description: "Optional case-insensitive substring of the card name" }
    },
    required: []
  )

  def self.call(server_context:, query: nil)
    user = current_user(server_context)
    scope = user.collections.with_cards.includes(:card)
    entries = scope.filter_map do |collection|
      next if query.present? && !collection.card.name.downcase.include?(query.downcase)

      availability = Allocations::Availability.call(user: user, card: collection.card)
      {
        card_id: collection.card_id,
        name: collection.card.name,
        owned: availability.owned,
        committed: availability.committed,
        available: availability.available
      }
    end
    text(entries.to_json)
  end
end
