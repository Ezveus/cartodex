module Mcp
  class ServerController < ActionController::API
    TOOLS = [
      AddCardToCollectionTool,
      AddCardToDeckTool,
      MoveCardToDeckTool,
      MoveCardFromDeckTool,
      SearchCardsTool,
      ListDecksTool,
      ListCollectionTool,
      ListDeckCardsTool
    ].freeze

    # Proxies to Rails.cache at call-time (rather than capturing it once at
    # class-load, as the `rate_limit` macro's `cache_store` default would),
    # so tests can swap Rails.cache for a real store and exercise throttling.
    RATE_LIMIT_STORE = Module.new do
      def self.increment(...)
        Rails.cache.increment(...)
      end
    end

    RATE_LIMIT_TO = 30
    RATE_LIMIT_WITHIN = 1.minute

    before_action :authenticate_token!
    rate_limit to: RATE_LIMIT_TO, within: RATE_LIMIT_WITHIN, store: RATE_LIMIT_STORE, only: :handle

    def handle
      server = MCP::Server.new(
        name: "cartodex",
        version: "1.0.0",
        tools: TOOLS,
        server_context: { user: @current_user }
      )
      transport = MCP::Server::Transports::StreamableHTTPTransport.new(server, stateless: true)
      status, headers, body = transport.handle_request(request)

      content_type = headers&.fetch("Content-Type", nil) || "application/json"
      render body: Array(body).join, content_type: content_type, status: status
    end

    private

    def authenticate_token!
      token = request.headers["Authorization"].to_s.delete_prefix("Bearer ").strip
      @current_user = User.authenticate_api_token(token)
      head :unauthorized unless @current_user
    end
  end
end
