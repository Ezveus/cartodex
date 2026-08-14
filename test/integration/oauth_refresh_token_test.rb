require "test_helper"

# Refresh-token rotation.
#
# Doorkeeper rotates lazily: redeeming a refresh token mints a new access token
# carrying `previous_refresh_token`, and the *old* refresh token is only revoked
# once the new access token is presented to a resource server. The gem fires
# that from Doorkeeper::OAuth::Token.authenticate, its single call site, on the
# doorkeeper_authorize! path. Mcp::ServerController resolves tokens itself, so
# it has to fire the hook itself — without it every refresh token ever issued
# stays redeemable forever and a replay is undetectable.
class OauthRefreshTokenTest < ActionDispatch::IntegrationTest
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

  # Runs the authorization code flow and returns the token endpoint's payload.
  def initial_tokens
    sign_in @user
    post "/oauth/authorize", params: {
      client_id: @application.uid, redirect_uri: @application.redirect_uri,
      response_type: "code", scope: "mcp:read mcp:write",
      code_challenge: @challenge, code_challenge_method: "S256"
    }
    code = Rack::Utils.parse_query(URI.parse(response.location).query)["code"]

    post "/oauth/token", params: {
      grant_type: "authorization_code", code: code,
      redirect_uri: @application.redirect_uri,
      client_id: @application.uid, client_secret: @application.plaintext_secret,
      code_verifier: @verifier
    }
    JSON.parse(response.body)
  end

  def refresh(refresh_token)
    post "/oauth/token", params: {
      grant_type: "refresh_token", refresh_token: refresh_token,
      client_id: @application.uid, client_secret: @application.plaintext_secret
    }
    JSON.parse(response.body)
  end

  def call_mcp(access_token)
    post "/mcp",
      params: { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} }.to_json,
      headers: {
        "Authorization" => "Bearer #{access_token}",
        "Content-Type" => "application/json",
        "Accept" => "application/json, text/event-stream"
      }
  end

  test "a refresh token is revoked once the access token it minted is used" do
    first = initial_tokens
    assert_response :success

    second = refresh(first["refresh_token"])
    assert_response :success
    assert second["access_token"].present?
    assert_not_equal first["refresh_token"], second["refresh_token"]

    # The grace window: the superseded refresh token is deliberately still alive
    # here, so two refreshes racing each other both succeed.
    assert_not Doorkeeper::AccessToken.by_refresh_token(first["refresh_token"]).revoked?

    call_mcp(second["access_token"])
    assert_response :success

    # Presenting the new access token is what closes the window.
    assert Doorkeeper::AccessToken.by_refresh_token(first["refresh_token"]).revoked?

    replay = refresh(first["refresh_token"])
    assert_response :bad_request
    assert_equal "invalid_grant", replay["error"]
  end

  test "the access token minted by a replayed refresh token never works" do
    # The end-to-end statement of the same fact, from the attacker's side: a
    # leaked refresh token buys nothing once the legitimate client has made one
    # call with the token it refreshed into.
    first = initial_tokens
    second = refresh(first["refresh_token"])
    call_mcp(second["access_token"])

    stolen = refresh(first["refresh_token"])

    assert_nil stolen["access_token"]
    assert_response :bad_request
  end

  test "settings still dates the connection from the consent, not the refresh" do
    # The seam between C1 and C2, driven through the real endpoints rather than
    # hand-made rows: rotation revokes the superseded AccessToken, so a
    # token-derived "connected since" would report the refresh date. The grant
    # created at consent is what actually records the authorization — and it is
    # revoked on redemption, so the derivation cannot look for an unrevoked one.
    travel_to Time.zone.parse("2026-07-15 10:00") do
      @first = initial_tokens
    end

    travel_to Time.zone.parse("2026-08-14 10:00") do
      second = refresh(@first["refresh_token"])
      call_mcp(second["access_token"])
      assert_response :success

      assert_equal 0, Doorkeeper::AccessGrant.where(revoked_at: nil).count,
        "the grant is revoked at redemption; an unrevoked-grant lookup would find nothing"
      assert_equal 1, Doorkeeper::AccessToken.where(revoked_at: nil).count,
        "rotation left exactly one live token, dated today"

      get settings_path
      assert_select "[data-testid='connected-app']", text: /connected July 15, 2026/
    end
  end

  test "rotating does not disturb a token that never superseded another" do
    # The first access token of a connection has no previous_refresh_token, so
    # the hook must be a no-op for it rather than revoking anything.
    first = initial_tokens

    call_mcp(first["access_token"])
    assert_response :success

    assert_not Doorkeeper::AccessToken.by_token(first["access_token"]).revoked?
    call_mcp(first["access_token"])
    assert_response :success
  end
end
