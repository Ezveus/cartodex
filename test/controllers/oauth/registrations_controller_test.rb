require "test_helper"

module Oauth
  class RegistrationsControllerTest < ActionDispatch::IntegrationTest
    def register(metadata)
      post "/oauth/register",
        params: metadata.to_json,
        headers: { "Content-Type" => "application/json" }
    end

    def valid_metadata
      {
        client_name: "Claude",
        redirect_uris: [ "https://claude.ai/api/mcp/auth_callback" ],
        token_endpoint_auth_method: "client_secret_post"
      }
    end

    test "registers a client and returns RFC 7591 credentials" do
      register(valid_metadata)

      assert_response :created
      body = JSON.parse(response.body)
      assert body["client_id"].present?
      assert body["client_secret"].present?
      assert body["client_id_issued_at"].present?
      # 0 means the secret does not expire, per RFC 7591.
      assert_equal 0, body["client_secret_expires_at"]
      assert_equal [ "https://claude.ai/api/mcp/auth_callback" ], body["redirect_uris"]
    end

    test "the returned credentials actually work at the token endpoint" do
      register(valid_metadata)
      credentials = JSON.parse(response.body)

      application = Doorkeeper::Application.find_by(uid: credentials["client_id"])
      assert_not_nil application
      assert application.secret_matches?(credentials["client_secret"])
    end

    test "omits client_secret for a public client" do
      register(valid_metadata.merge(token_endpoint_auth_method: "none"))

      assert_response :created
      assert_nil JSON.parse(response.body)["client_secret"]
    end

    test "rejects a redirect host outside the allowlist" do
      register(valid_metadata.merge(redirect_uris: [ "https://evil.example.com/cb" ]))

      assert_response :bad_request
      assert_equal "invalid_redirect_uri", JSON.parse(response.body)["error"]
      assert_equal 0, Doorkeeper::Application.count
    end

    test "requires no authentication" do
      register(valid_metadata)

      assert_response :created
    end
  end
end
