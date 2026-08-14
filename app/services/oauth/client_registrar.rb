module Oauth
  # RFC 7591 dynamic client registration.
  #
  # The endpoint that calls this is necessarily unauthenticated — a client has no
  # credential before it registers. That makes the redirect-URI allowlist the
  # load-bearing control: without it, anyone can register a client pointing at
  # their own server, name it "Claude", and phish a Cartodex user into
  # authorizing it. client_name comes straight from the request and is entirely
  # attacker-controlled, so it can never be part of a security decision.
  class ClientRegistrar < ApplicationService
    class InvalidMetadata < StandardError
      attr_reader :code

      def initialize(code, message)
        @code = code
        super(message)
      end
    end

    # Anthropic asks operators to allowlist both of its callback hosts:
    # claude.ai is current, claude.com is the announced successor. The loopback
    # hosts cover CLI clients, which bind an ephemeral local port.
    ALLOWED_REDIRECT_HOSTS = %w[claude.ai claude.com localhost 127.0.0.1].freeze

    # Only the loopback hosts may drop TLS: there is no network to intercept.
    PLAIN_HTTP_HOSTS = %w[localhost 127.0.0.1].freeze

    SERVER_SCOPES = %w[mcp:read mcp:write].freeze

    def initialize(metadata)
      @metadata = metadata
    end

    def call
      Doorkeeper::Application.create!(
        name: client_name,
        redirect_uri: redirect_uris.join("\n"),
        scopes: scopes,
        confidential: confidential?
      )
    end

    private

    attr_reader :metadata

    def client_name
      name = metadata["client_name"].to_s.strip
      name.presence || "Unnamed MCP client"
    end

    def redirect_uris
      uris = Array(metadata["redirect_uris"]).map(&:to_s).reject(&:blank?)
      raise InvalidMetadata.new("invalid_redirect_uri", "redirect_uris is required") if uris.empty?

      uris.each { |uri| validate_redirect_uri!(uri) }
    end

    def validate_redirect_uri!(raw)
      uri = URI.parse(raw)
      reject_uri!(raw) unless uri.absolute? && uri.fragment.nil?
      reject_uri!(raw) unless ALLOWED_REDIRECT_HOSTS.include?(uri.host)
      reject_uri!(raw) unless uri.scheme == "https" ||
                              (uri.scheme == "http" && PLAIN_HTTP_HOSTS.include?(uri.host))
    rescue URI::InvalidURIError
      reject_uri!(raw)
    end

    def reject_uri!(raw)
      raise InvalidMetadata.new("invalid_redirect_uri", "#{raw} is not an acceptable redirect URI")
    end

    # A client that names no scope gets both, which is what Claude does when it
    # follows scopes_supported from the protected-resource document. The consent
    # screen, not registration, is where a user narrows this down.
    def scopes
      requested = metadata["scope"].to_s.split
      return SERVER_SCOPES.join(" ") if requested.empty?

      unknown = requested - SERVER_SCOPES
      if unknown.any?
        raise InvalidMetadata.new("invalid_client_metadata", "unknown scope: #{unknown.join(' ')}")
      end

      requested.join(" ")
    end

    def confidential?
      metadata["token_endpoint_auth_method"].to_s != "none"
    end
  end
end
