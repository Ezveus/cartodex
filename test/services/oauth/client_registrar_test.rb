require "test_helper"

module Oauth
  class ClientRegistrarTest < ActiveSupport::TestCase
    def metadata(overrides = {})
      {
        "client_name" => "Claude",
        "redirect_uris" => [ "https://claude.ai/api/mcp/auth_callback" ],
        "grant_types" => %w[authorization_code refresh_token],
        "response_types" => [ "code" ],
        "token_endpoint_auth_method" => "client_secret_post",
        "scope" => "mcp:read mcp:write"
      }.merge(overrides)
    end

    test "creates a confidential application for an allowlisted redirect host" do
      application = ClientRegistrar.call(metadata)

      assert_equal "Claude", application.name
      assert_equal "https://claude.ai/api/mcp/auth_callback", application.redirect_uri
      assert_equal "mcp:read mcp:write", application.scopes.to_s
      assert application.confidential?
    end

    test "accepts claude.com as well as claude.ai" do
      application = ClientRegistrar.call(
        metadata("redirect_uris" => [ "https://claude.com/api/mcp/auth_callback" ])
      )

      assert_equal "https://claude.com/api/mcp/auth_callback", application.redirect_uri
    end

    test "accepts a loopback callback over plain HTTP for CLI clients" do
      application = ClientRegistrar.call(
        metadata("redirect_uris" => [ "http://127.0.0.1:49152/callback" ])
      )

      assert_equal "http://127.0.0.1:49152/callback", application.redirect_uri
    end

    test "creates a public application when the client authenticates with none" do
      application = ClientRegistrar.call(metadata("token_endpoint_auth_method" => "none"))

      assert_not application.confidential?
    end

    test "rejects a redirect host outside the allowlist" do
      error = assert_raises(ClientRegistrar::InvalidMetadata) do
        ClientRegistrar.call(metadata("redirect_uris" => [ "https://evil.example.com/callback" ]))
      end

      assert_equal "invalid_redirect_uri", error.code
      assert_equal 0, Doorkeeper::Application.count
    end

    test "rejects plain HTTP on a non-loopback host" do
      error = assert_raises(ClientRegistrar::InvalidMetadata) do
        ClientRegistrar.call(metadata("redirect_uris" => [ "http://claude.ai/api/mcp/auth_callback" ]))
      end

      assert_equal "invalid_redirect_uri", error.code
    end

    test "rejects a redirect URI carrying a fragment" do
      error = assert_raises(ClientRegistrar::InvalidMetadata) do
        ClientRegistrar.call(
          metadata("redirect_uris" => [ "https://claude.ai/api/mcp/auth_callback#x" ])
        )
      end

      assert_equal "invalid_redirect_uri", error.code
    end

    test "rejects metadata with no redirect_uris at all" do
      error = assert_raises(ClientRegistrar::InvalidMetadata) do
        ClientRegistrar.call(metadata.except("redirect_uris"))
      end

      assert_equal "invalid_redirect_uri", error.code
    end

    test "rejects a scope outside the server's own" do
      error = assert_raises(ClientRegistrar::InvalidMetadata) do
        ClientRegistrar.call(metadata("scope" => "mcp:read admin"))
      end

      assert_equal "invalid_client_metadata", error.code
    end

    test "falls back to both scopes when the client requests none" do
      application = ClientRegistrar.call(metadata.except("scope"))

      assert_equal "mcp:read mcp:write", application.scopes.to_s
    end
  end
end
