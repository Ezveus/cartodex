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
      SetDeckCardPrintingTool,
      SuggestOwnedEquivalentsTool,
      ListPrintingsTool
    ].freeze

    # Proxies to Rails.cache at call-time (rather than capturing it once at
    # class-load, as the `rate_limit` macro's `cache_store` default would),
    # so tests can swap Rails.cache for a real store and exercise throttling.
    RATE_LIMIT_STORE = Module.new do
      def self.increment(...)
        Rails.cache.increment(...)
      end
    end

    IP_RATE_LIMIT_TO = 30
    IP_RATE_LIMIT_WITHIN = 1.minute

    USER_RATE_LIMIT_TO = 300
    USER_RATE_LIMIT_WITHIN = 1.minute

    # RFC 6750 §2.1 defines the credentials as "Bearer" 1*SP b64token, and
    # RFC 7235 §2.1 makes the scheme name case-insensitive — "bearer <token>"
    # is as valid as "Bearer <token>", and clients do send it.
    BEARER_SCHEME = /\ABearer\s+/i

    # Hostnames legitimately serving this app, checked by the mcp gem's DNS
    # rebinding protection (added in 0.23) against the request's Host header.
    # Loopback hosts are allowed by the gem itself.
    #
    # "www.example.com" is Rails' ActionDispatch::Integration::Session default
    # test host, and it exists here only so the suite can reach the endpoint. It
    # is admitted outside production only: shipping it would hand a production
    # DNS-rebinding attempt a Host header this app has no reason to serve.
    #
    # A method rather than a bare literal so the production membership is
    # assertable from a test that itself runs in the test environment.
    def self.allowed_hosts(env = Rails.env)
      [ "cartodex.ezveus.eu", ("www.example.com" unless env.production?) ].compact
    end

    ALLOWED_HOSTS = allowed_hosts.freeze

    # Two limiters, and their positions in the callback chain matter. Both are
    # plain before_actions (`rate_limit` forwards its options straight to
    # `before_action`), so both run on every request that reaches them and an
    # authenticated request is bound by whichever budget it exhausts first.
    #
    # Authentication is therefore split in two: identify_token_user resolves
    # the bearer token without halting, and reject_unauthenticated! issues the
    # 401 afterwards. That lets each limiter sit exactly where it belongs.
    before_action :identify_token_user

    # Anti-abuse for anonymous traffic, which has no identity other than its
    # IP. `unless:` restricts it to requests that failed to authenticate, so it
    # never eats into a legitimate client's quota — the whole point of the
    # split, since an authenticated MCP session routinely burns far more than
    # IP_RATE_LIMIT_TO calls a minute (importing a decklist card by card is
    # ~60), and several users can share one egress IP.
    #
    # The tradeoff: this limiter now runs *after* the token digest lookup
    # instead of before it. What it still protects is the application — the MCP
    # server, tool dispatch, and every query behind it stay unreachable to
    # invalid-token spam beyond IP_RATE_LIMIT_TO per minute. What it no longer
    # protects is the database: each rejected attempt costs one indexed lookup
    # in User.authenticate_api_token before it is counted, where previously a
    # request past the limit was refused with zero database work. Accepted
    # because that lookup is a single indexed read on a digest, and because
    # anything cheaper would have to throttle authenticated users by IP.
    rate_limit to: IP_RATE_LIMIT_TO, within: IP_RATE_LIMIT_WITHIN,
      name: "mcp-ip", unless: -> { @current_user },
      store: RATE_LIMIT_STORE, only: :handle

    before_action :reject_unauthenticated!

    # The work quota. Keyed by user id rather than by IP because an IP is not a
    # usable identity for an authenticated client here: MCP clients are
    # increasingly server-side (Claude web connectors call from shared,
    # rotating provider egress IPs, and two local agents on one machine share a
    # home NAT), so an IP-keyed quota either lumps unrelated users into one
    # bucket or follows a single user around as they change IPs.
    #
    # Both limiters pass an explicit `name:` so they get distinct cache keys.
    rate_limit to: USER_RATE_LIMIT_TO, within: USER_RATE_LIMIT_WITHIN,
      by: -> { @current_user.id },
      name: "mcp-user", store: RATE_LIMIT_STORE, only: :handle

    # Scopes are enforced by what the server is even told about. A tool absent
    # from this list is absent from tools/list and unroutable by tools/call, so a
    # client that guesses a name gets "tool not found" rather than a refusal.
    #
    # This is a deliberate departure from the specification's step-up flow, which
    # expects a 403 insufficient_scope. Producing that would mean parsing the
    # JSON-RPC body here to learn which tool was called, duplicating the dispatch
    # the mcp gem owns. The client learns the same thing at tools/list instead —
    # earlier, and without us reimplementing the protocol. See the design spec.
    def handle
      server = MCP::Server.new(
        name: "cartodex",
        version: "1.0.0",
        tools: McpTool.permitted_for(TOOLS, @current_scopes),
        server_context: { user: @current_user }
      )
      # `serve_subscriptions_listen: false` because this action buffers: it joins
      # the body into a single `render`. The SEP-2575 `subscriptions/listen`
      # stream (mcp 1.2) is intercepted by the transport rather than dispatched
      # through the server, so declaring no resources does not put it out of
      # reach, and it answers with a Rack streaming body that responds to `call`
      # and not to `each` — which `Array(body).join` would serve as the object's
      # own `#to_s`, a 200 carrying an inspection string. Declining the method
      # makes it fall through to the dispatcher as unimplemented (-32601), the
      # honest answer from a host that cannot hold an SSE response open.
      transport = MCP::Server::Transports::StreamableHTTPTransport.new(
        server, stateless: true, allowed_hosts: ALLOWED_HOSTS,
        serve_subscriptions_listen: false
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

    # Deliberately does not halt the chain: the per-IP limiter is declared
    # between this and reject_unauthenticated! and needs to know whether the
    # request authenticated before deciding to count it.
    def identify_token_user
      token = request.headers["Authorization"].to_s.sub(BEARER_SCHEME, "").strip
      authenticate_oauth_token(token) || authenticate_legacy_token(token)
    end

    def reject_unauthenticated!
      challenge! if @current_user.nil?
    end

    # An OAuth 2.1 access token issued by this app's own authorization server.
    # `accessible?` covers both expiry and revocation, so a revoked client's
    # tokens stop working the moment the user revokes it in /settings.
    def authenticate_oauth_token(token)
      access_token = Doorkeeper::AccessToken.by_token(token)
      return false unless access_token&.accessible?

      rotate_refresh_token(access_token)

      @current_user = User.find_by(id: access_token.resource_owner_id)
      return false if @current_user.nil?

      @current_scopes = access_token.scopes.to_a
      true
    end

    # Retires the credential row this access token superseded — the whole row,
    # access token included, not just its refresh token. A client still holding
    # requests in flight on the old access token therefore gets 401 from the
    # moment it presents the new one. That is standard revoked-on-use behaviour
    # and no client is harmed by it (a 401 on /mcp starts a refresh), but it is
    # worth stating, because "rotate the refresh token" undersells what happens.
    #
    # Doorkeeper rotates lazily: a refresh mints a new access token carrying
    # `previous_refresh_token`, and the old row is revoked only once the *new*
    # access token is presented to a resource server. The gem fires that from
    # `Doorkeeper::OAuth::Token.authenticate`, its one and only call site
    # (`lib/doorkeeper/oauth/token.rb:19`), on the `doorkeeper_authorize!` path.
    # This controller resolves tokens itself, so without this line the hook never
    # runs and no refresh token is ever retired.
    #
    # Firing it here rather than at the token endpoint is deliberate — it keeps
    # Doorkeeper's concurrency grace window, where two racing refreshes both
    # succeed because the old token survives until the new one is actually used.
    #
    # What this does and does not buy, stated precisely because it is easy to
    # overstate: rotation bounds a **passively** leaked refresh token — one an
    # attacker holds but has not redeemed — because the legitimate client's next
    # refresh-then-call retires it. It is NOT RFC 9700 reuse detection. An
    # attacker who redeems a stolen refresh token inside the grace window mints
    # their own chain; when the legitimate client later refreshes, the shared
    # ancestor is already revoked, `revoke` early-returns, and the attacker's
    # chain survives independently — refreshable indefinitely and grouped into
    # the same /settings row as the user's own. Reuse detection is not
    # implemented because, under the concurrency grace window this design keeps
    # on purpose, a replay is not distinguishable from a legitimate double
    # refresh. The reliable remedy against an active attacker is the user
    # revoking the connection, which does kill both chains at once.
    #
    # Doorkeeper 5.9.6 also has no `refresh_token_expires_in` — the option does
    # not exist in the gem — so rotation plus that revocation is the whole bound
    # on a refresh token's life. See the design spec.
    def rotate_refresh_token(access_token)
      access_token.revoke_previous_refresh_token! if Doorkeeper.config.refresh_token_enabled?
    end

    # Deprecated. The static per-user bearer token predates OAuth and stays only
    # so existing CLI configurations keep working; it is scheduled for removal
    # once OAuth has been verified against a real connector. It carries no
    # scopes, so it keeps full access — narrowing it now would break the very
    # setups this branch exists to preserve.
    def authenticate_legacy_token(token)
      @current_user = User.authenticate_api_token(token)
      @current_scopes = nil
      @current_user.present?
    end

    # RFC 9728: the 401 tells the client where to find the metadata that starts
    # the authorization flow. The challenge is byte-identical whether the token
    # was absent, unknown, expired or revoked — distinguishing them would let a
    # caller probe which tokens exist.
    def challenge!
      response.headers["WWW-Authenticate"] =
        %(Bearer resource_metadata="#{root_url.chomp('/')}/.well-known/oauth-protected-resource/mcp")
      head :unauthorized
    end
  end
end
