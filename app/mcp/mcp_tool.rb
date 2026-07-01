# Base class for Cartodex MCP tools. Provides helpers for resolving the
# authenticated user (passed through server_context), looking up owned records,
# and building text responses.
class McpTool < MCP::Tool
  class << self
    # MCP::Tool::name_value defaults to the full snake_cased class name (e.g.
    # "add_card_to_collection_tool"), but the wire protocol name clients call
    # should omit the "_tool" suffix (e.g. "add_card_to_collection"). Strip it
    # here so every subclass gets the client-facing name for free.
    def name_value
      super&.delete_suffix("_tool")
    end

    private

    def current_user(server_context)
      server_context.fetch(:user)
    end

    def find_card!(id)
      Card.find(id)
    end

    def find_deck!(user, id)
      user.decks.find(id)
    end

    def text(string)
      MCP::Tool::Response.new([ { type: "text", text: string } ])
    end
  end
end
