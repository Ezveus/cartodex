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
      @current_user = User.find_by(api_token: token) if token.present?
      head :unauthorized unless @current_user
    end
  end
end
