module Oauth
  # RFC 8707 resource indicators. Doorkeeper 5.9 ignores the parameter entirely
  # (6.0 gains resource_indicator_validator), so both endpoints check it here.
  #
  # Cartodex hosts exactly one protected resource, so "was this token issued for
  # us" reduces to "does the requested resource name us". THAT EQUIVALENCE ENDS
  # THE DAY A SECOND PROTECTED RESOURCE EXISTS: at that point the resource has to
  # be stored on the token and re-checked when the token is presented.
  module ResourceIndicator
    module_function

    # The one definition of what "this resource" means. Both the metadata
    # document (which advertises it) and the two OAuth endpoints (which validate
    # against it) call this, so the advertised value and the accepted value
    # cannot drift apart.
    def canonical_uri(root_url)
      "#{root_url.chomp('/')}/mcp"
    end

    # Absent is acceptable; present and wrong is not.
    def valid?(value, canonical_uri)
      return true if value.blank?

      uri = URI.parse(value.to_s)
      return false unless uri.fragment.nil?

      # RFC 8707 canonical form is lowercase scheme and host, but the MCP
      # specification asks servers to accept uppercase for robustness. The path
      # is compared as-is: it is case-sensitive by RFC 3986.
      normalize(uri) == canonical_uri
    rescue URI::InvalidURIError
      false
    end

    def normalize(uri)
      "#{uri.scheme&.downcase}://#{uri.host&.downcase}#{":#{uri.port}" unless uri.default_port == uri.port}#{uri.path.chomp('/')}"
    end
  end
end
