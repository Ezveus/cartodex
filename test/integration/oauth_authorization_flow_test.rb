require "test_helper"

class OauthAuthorizationFlowTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @application = Doorkeeper::Application.create!(
      name: "Test Client",
      redirect_uri: "https://claude.ai/api/mcp/auth_callback",
      scopes: "mcp:read mcp:write"
    )
    @verifier = SecureRandom.urlsafe_base64(64)
    @challenge = Base64.urlsafe_encode64(
      Digest::SHA256.digest(@verifier), padding: false
    )
  end

  def authorize_params(overrides = {})
    {
      client_id: @application.uid,
      redirect_uri: @application.redirect_uri,
      response_type: "code",
      scope: "mcp:read mcp:write",
      code_challenge: @challenge,
      code_challenge_method: "S256"
    }.merge(overrides)
  end

  # Pulls the authorization code out of the redirect Doorkeeper issues.
  def code_from_redirect
    Rack::Utils.parse_query(URI.parse(response.location).query)["code"]
  end

  test "issues an access token through the authorization code flow with PKCE" do
    sign_in @user

    post "/oauth/authorize", params: authorize_params
    assert_response :redirect

    post "/oauth/token", params: {
      grant_type: "authorization_code",
      code: code_from_redirect,
      redirect_uri: @application.redirect_uri,
      client_id: @application.uid,
      client_secret: @application.plaintext_secret,
      code_verifier: @verifier
    }

    assert_response :success
    body = JSON.parse(response.body)
    assert body["access_token"].present?
    assert body["refresh_token"].present?
    assert_equal "mcp:read mcp:write", body["scope"]

    token = Doorkeeper::AccessToken.by_token(body["access_token"])
    assert_equal @user.id, token.resource_owner_id
  end

  test "rejects an authorization request that omits the PKCE challenge" do
    sign_in @user

    assert_no_difference -> { Doorkeeper::AccessGrant.count } do
      post "/oauth/authorize", params: authorize_params.except(:code_challenge, :code_challenge_method)
    end

    # force_pkce turns a missing challenge into a redirect carrying an
    # invalid_request error, rather than silently issuing a code that any
    # interceptor could redeem. Doorkeeper redirects a rejected request back
    # to the client's *valid, registered* redirect_uri exactly the way it
    # redirects a successful grant (both are HTTP 302, per RFC 6749 error
    # handling), so the rejection has to be read from the query string, not
    # the HTTP status code.
    assert_response :redirect
    query = Rack::Utils.parse_query(URI.parse(response.location).query)
    assert_equal "invalid_request", query["error"]
    assert_nil query["code"]
  end

  test "rejects a token exchange with the wrong code verifier" do
    sign_in @user
    post "/oauth/authorize", params: authorize_params
    code = code_from_redirect

    post "/oauth/token", params: {
      grant_type: "authorization_code",
      code: code,
      redirect_uri: @application.redirect_uri,
      client_id: @application.uid,
      client_secret: @application.plaintext_secret,
      code_verifier: SecureRandom.urlsafe_base64(64)
    }

    assert_response :bad_request
    assert_equal "invalid_grant", JSON.parse(response.body)["error"]
  end

  test "refuses to redeem the same authorization code twice" do
    sign_in @user
    post "/oauth/authorize", params: authorize_params
    code = code_from_redirect

    exchange = lambda do
      post "/oauth/token", params: {
        grant_type: "authorization_code",
        code: code,
        redirect_uri: @application.redirect_uri,
        client_id: @application.uid,
        client_secret: @application.plaintext_secret,
        code_verifier: @verifier
      }
    end

    exchange.call
    assert_response :success

    exchange.call
    assert_response :bad_request
    assert_equal "invalid_grant", JSON.parse(response.body)["error"]
  end
end
