class ListDecksTool < McpTool
  description "List the authenticated user's decks with their ids, names, and formats."
  input_schema(properties: {}, required: [])

  def self.call(server_context:)
    user = current_user(server_context)
    decks = user.decks.map do |deck|
      { id: deck.id, name: deck.name, format: deck.format }
    end
    text(decks.to_json)
  end
end
