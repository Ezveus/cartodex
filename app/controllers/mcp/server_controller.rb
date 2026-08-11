module Mcp
  class ServerController < ActionController::API
    TOOLS = [
      AddCardToCollectionTool,
      AddCardToDeckTool,
      SetCollectionQuantityTool,
      SearchCardsTool,
      ListDecksTool,
      ListCollectionTool,
      ListDeckCardsTool,
      ListOverAllocationsTool,
      SetDeckCardOwnedCopiesTool,
      ReallocateOwnedCopiesTool,
      SetDeckCardQuantityTool,
      SuggestOwnedEquivalentsTool
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

    # Hostnames legitimately serving this app, checked by the mcp gem's DNS
    # rebinding protection (added in 0.23) against the request's Host header.
    # "www.example.com" is Rails' ActionDispatch::Integration::Session default
    # test host; loopback hosts are allowed by the gem itself.
    ALLOWED_HOSTS = [ "cartodex.ezveus.eu", "www.example.com" ].freeze

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
      transport = MCP::Server::Transports::StreamableHTTPTransport.new(
        server, stateless: true, allowed_hosts: ALLOWED_HOSTS
      )
      status, headers, body = transport.handle_request(request)

      render body: Array(body).join, content_type: content_type_of(headers), status: status
    end

    private

    # The transport hands back a Rack-style header hash whose key casing is not
    # part of its contract: it was "Content-Type" up to mcp 0.24 and became
    # "content-type" in 0.25. Match either, so a stream never gets mislabelled
    # as JSON. Today every reachable response is JSON anyway — `stateless: true`
    # answers GET with 405, so the transport's text/event-stream headers are out
    # of reach — but the route already accepts GET, so dropping stateless mode
    # would make the casing matter.
    def content_type_of(headers)
      headers&.find { |name, _| name.to_s.casecmp?("content-type") }&.last || "application/json"
    end

    def authenticate_token!
      token = request.headers["Authorization"].to_s.delete_prefix("Bearer ").strip
      @current_user = User.authenticate_api_token(token)
      head :unauthorized unless @current_user
    end
  end
end
