require "test_helper"

module Oauth
  class MetadataControllerTest < ActionDispatch::IntegrationTest
    test "protected resource metadata points at this server and its scopes" do
      get "/.well-known/oauth-protected-resource"

      assert_response :success
      assert_equal "application/json", response.media_type
      body = JSON.parse(response.body)

      # The resource value must match the MCP URL exactly — a client that finds a
      # mismatch here is expected to abandon the flow.
      assert_equal "#{root_url.chomp('/')}/mcp", body["resource"]
      assert_equal [ root_url.chomp("/") ], body["authorization_servers"]
      assert_equal %w[mcp:read mcp:write], body["scopes_supported"]
      assert_equal [ "header" ], body["bearer_methods_supported"]
    end

    test "serves the protected resource metadata at the path-suffixed location too" do
      # RFC 9728 has the client insert the well-known segment before the
      # resource's path, so /mcp resolves to this URL. Clients disagree in
      # practice, so both must answer, identically.
      get "/.well-known/oauth-protected-resource/mcp"
      assert_response :success
      suffixed = response.body

      get "/.well-known/oauth-protected-resource"
      assert_equal suffixed, response.body
    end

    test "authorization server metadata advertises the endpoints and PKCE" do
      get "/.well-known/oauth-authorization-server"

      assert_response :success
      body = JSON.parse(response.body)

      assert_equal root_url.chomp("/"), body["issuer"]
      assert_equal "#{root_url.chomp('/')}/oauth/authorize", body["authorization_endpoint"]
      assert_equal "#{root_url.chomp('/')}/oauth/token", body["token_endpoint"]
      assert_equal "#{root_url.chomp('/')}/oauth/register", body["registration_endpoint"]
      assert_equal [ "code" ], body["response_types_supported"]
      assert_equal %w[authorization_code refresh_token], body["grant_types_supported"]
      assert_equal [ "S256" ], body["code_challenge_methods_supported"]
      assert_equal %w[mcp:read mcp:write], body["scopes_supported"]
    end

    test "metadata is reachable without authentication" do
      get "/.well-known/oauth-protected-resource"
      assert_response :success
      get "/.well-known/oauth-authorization-server"
      assert_response :success
    end
  end
end
