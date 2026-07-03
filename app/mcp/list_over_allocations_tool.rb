class ListOverAllocationsTool < McpTool
  description "List cards whose real copies committed across physical decks exceed what the user owns (decks to review), with the decks involved."
  input_schema(properties: {}, required: [])

  def self.call(server_context:)
    user = current_user(server_context)
    text(Allocations::OverAllocations.call(user: user).to_json)
  end
end
