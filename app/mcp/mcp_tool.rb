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
      @name_value || super.delete_suffix("_tool")
    end

    # Which OAuth scope a tool needs. Read is the default because it is the safe
    # one: a tool added later without thinking about scopes stays read-only
    # rather than silently escaping the write restriction.
    def required_scope(scope = nil)
      @required_scope = scope if scope
      @required_scope || "mcp:read"
    end

    # Tools a token may use. A nil scope list means the legacy static token,
    # which predates scopes entirely and keeps full access for its deprecation
    # window.
    def permitted_for(tools, scopes)
      return tools if scopes.nil?

      tools.select { |tool| scopes.include?(tool.required_scope) }
    end

    private

    def current_user(server_context)
      server_context.fetch(:user)
    end

    def find_card!(id)
      Card.find(id)
    end

    def find_deck!(user, key)
      user.decks.find_by!(key: key)
    end

    def text(string)
      MCP::Tool::Response.new([ { type: "text", text: string } ])
    end

    # Guard for write tools: the JSON schema already rejects quantity < 1 on
    # real MCP calls, but a direct in-process call bypasses that, so tools that
    # only add copies validate explicitly before touching the database.
    def positive_quantity?(quantity)
      quantity.is_a?(Integer) && quantity.positive?
    end

    def quantity_error(quantity)
      text("Error: quantity must be a positive integer (got #{quantity.inspect}).")
    end
  end
end
