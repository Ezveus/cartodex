module Oauth
  # The two discovery documents an MCP client fetches before it can authenticate:
  # RFC 9728 protected resource metadata (which authorization server guards this
  # resource) and RFC 8414 authorization server metadata (where its endpoints
  # are). Doorkeeper 5.9 ships neither; 6.0 ships the second one, at which point
  # #authorization_server can be dropped in favour of the gem's.
  #
  # Both are public and identical for every caller, so they are cacheable and
  # deliberately free of any request-derived state beyond the host.
  class MetadataController < ActionController::API
    SCOPES = %w[mcp:read mcp:write].freeze

    def protected_resource
      render json: {
        resource: canonical_resource_uri,
        authorization_servers: [ issuer ],
        scopes_supported: SCOPES,
        bearer_methods_supported: [ "header" ]
      }
    end

    def authorization_server
      render json: {
        issuer: issuer,
        authorization_endpoint: "#{issuer}/oauth/authorize",
        token_endpoint: "#{issuer}/oauth/token",
        registration_endpoint: "#{issuer}/oauth/register",
        revocation_endpoint: "#{issuer}/oauth/revoke",
        response_types_supported: [ "code" ],
        grant_types_supported: %w[authorization_code refresh_token],
        code_challenge_methods_supported: [ "S256" ],
        token_endpoint_auth_methods_supported: %w[client_secret_basic client_secret_post none],
        scopes_supported: SCOPES
      }
    end

    private

    # Derived from the request rather than hardcoded so development, test and
    # production each advertise themselves. The canonical form carries no
    # trailing slash — RFC 8707 asks for the most specific URI, consistently
    # written, and a client comparing strings will not normalise for us.
    def issuer
      root_url.chomp("/")
    end

    def canonical_resource_uri
      ResourceIndicator.canonical_uri(root_url)
    end
  end
end
