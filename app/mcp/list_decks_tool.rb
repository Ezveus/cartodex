class ListDecksTool < McpTool
  description "List the authenticated user's decks with their keys, names, formats and Standard pool."
  input_schema(properties: {}, required: [])

  def self.call(server_context:)
    user = current_user(server_context)
    decks = user.decks.with_standard_pool.map do |deck|
      { key: deck.key, name: deck.name, format: deck.format, standard_pool: deck.standard_pool&.name,
        physical: deck.physical, tcg_live: deck.tcg_live }
    end
    text(decks.to_json)
  end
end
