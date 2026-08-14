require "test_helper"

class OauthConsentTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @application = Doorkeeper::Application.create!(
      name: "Claude",
      redirect_uri: "https://claude.ai/api/mcp/auth_callback",
      scopes: "mcp:read mcp:write"
    )
    @verifier = SecureRandom.urlsafe_base64(64)
    @challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(@verifier), padding: false)
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

  def granted_scopes
    code = Rack::Utils.parse_query(URI.parse(response.location).query)["code"]
    # AccessGrant#token is hashed in storage (hash_token_secrets, see
    # config/initializers/doorkeeper.rb) — .by_token hashes the lookup value
    # the same way; a plain find_by(token:) against the plaintext code would
    # never match.
    Doorkeeper::AccessGrant.by_token(code)&.scopes.to_s
  end

  test "redirects an anonymous visitor to sign in and back to the authorization" do
    get "/oauth/authorize", params: authorize_params

    assert_redirected_to new_user_session_path
  end

  test "shows the client name and the redirect host on the consent screen" do
    sign_in @user

    get "/oauth/authorize", params: authorize_params

    assert_response :success
    assert_select "[data-testid='consent-client-name']", text: /Claude/
    # The name is self-declared and worthless as identity; the host is what a
    # user can actually judge, so it must be on screen.
    assert_select "[data-testid='consent-redirect-host']", text: /claude\.ai/
  end

  test "grants both scopes when write is left checked" do
    sign_in @user

    post "/oauth/authorize", params: authorize_params

    assert_response :redirect
    assert_equal "mcp:read mcp:write", granted_scopes
  end

  test "grants read only when write is unchecked" do
    sign_in @user

    # Unchecking the box makes the browser post the narrower scope string.
    post "/oauth/authorize", params: authorize_params(scope: "mcp:read")

    assert_response :redirect
    assert_equal "mcp:read", granted_scopes
  end

  test "escapes a client name that tries to inject markup" do
    @application.update!(name: "<script>alert(1)</script>")
    sign_in @user

    get "/oauth/authorize", params: authorize_params

    assert_response :success
    assert_not_includes response.body, "<script>alert(1)</script>"
  end
end
