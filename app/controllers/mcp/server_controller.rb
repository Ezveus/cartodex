module Mcp
  class ServerController < ActionController::API
    TOOLS = [
      AddCardToCollectionTool,
      AddCardToDeckTool,
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

    # `rate_limit` registers its own before_action at the point it's declared,
    # and before_actions run in declaration order. It must be declared before
    # authenticate_token! so invalid/missing-token requests are throttled too
    # (otherwise authenticate_token!'s `head :unauthorized` halts the chain
    # before the limiter ever runs, letting attackers spam tokens unthrottled).
    rate_limit to: RATE_LIMIT_TO, within: RATE_LIMIT_WITHIN, store: RATE_LIMIT_STORE, only: :handle
    before_action :authenticate_token!

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
