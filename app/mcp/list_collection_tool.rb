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
    # Filtered in SQL rather than in Ruby after loading every row, through the
    # same Collection scope the collection page uses: case-insensitive even on
    # accented letters, with a `%` or `_` in the query matched literally.
    scope = scope.card_name_matching(query) if query.present?
    collections = scope.to_a

    # One batched lookup instead of one Availability call per row, which was an
    # N+1 that grew with the user's collection.
    availability = Allocations::Availability.for_cards(user: user, cards: collections.map(&:card))

    entries = collections.map do |collection|
      numbers = availability[collection.card_id]
      {
        card_id: collection.card_id,
        name: collection.card.name,
        owned: numbers.owned,
        committed: numbers.committed,
        available: numbers.available
      }
    end
    text(entries.to_json)
  end
end
