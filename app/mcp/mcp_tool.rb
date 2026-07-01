# Base class for Cartodex MCP tools. Provides helpers for resolving the
# authenticated user (passed through server_context), looking up owned records,
# and building text responses.
class McpTool < MCP::Tool
  class << self
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
