require "test_helper"
require_relative "../support/oauth_consent_form"

class OauthConsentTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include OauthConsentForm

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
    redeemed_grant&.scopes.to_s
  end

  def redeemed_grant
    code = Rack::Utils.parse_query(URI.parse(response.location).query)["code"]
    # AccessGrant#token is hashed in storage (hash_token_secrets, see
    # config/initializers/doorkeeper.rb) — .by_token hashes the lookup value
    # the same way; a plain find_by(token:) against the plaintext code would
    # never match.
    Doorkeeper::AccessGrant.by_token(code)
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

  test "round-trips through the rendered form with write checked" do
    sign_in @user

    get "/oauth/authorize", params: authorize_params
    assert_response :success
    post "/oauth/authorize", params: harvest_form_params

    assert_response :redirect
    assert_equal "mcp:read mcp:write", granted_scopes
    # The one assertion that makes it impossible to silently drop
    # code_challenge (or code_challenge_method) from the hidden fields: a
    # missing/mismatched challenge here means PKCE was downgraded for anyone
    # who went through this screen.
    assert_equal @challenge, redeemed_grant.code_challenge
  end

  test "round-trips through the rendered form with write unchecked" do
    sign_in @user

    get "/oauth/authorize", params: authorize_params
    assert_response :success
    # Simulates unchecking the mcp:write box: it is a real, non-disabled
    # checkbox, so leaving its value out of the harvest is exactly what a
    # browser would send.
    post "/oauth/authorize", params: harvest_form_params(exclude_checkbox_values: [ "mcp:write" ])

    assert_response :redirect
    assert_equal "mcp:read", granted_scopes
  end

  test "renders inside Cartodex's own layout, not Doorkeeper's" do
    # Doorkeeper's controllers descend from ActionController::Base, so layout
    # lookup climbs to layouts/doorkeeper/application — the gem's, which pulls
    # in doorkeeper/application.css and none of ours. Every class and every
    # design token this screen uses would then be undefined.
    #
    # That matters here more than anywhere else in the app: the only defence
    # against a client that registered itself as "Claude" is the user
    # recognising this page as Cartodex and reading the redirect host on it.
    #
    # The body-content assertions above are structurally blind to this — they
    # pass identically under either layout, which is exactly how it shipped.
    sign_in @user

    get "/oauth/authorize", params: authorize_params

    assert_response :success
    assert_select "head link[rel=stylesheet][href^='/assets/application-']", count: 1
    assert_select "head link[rel=stylesheet][href*='doorkeeper']", count: 0
    assert_select "head title", text: "Cartodex"
    # The app's own chrome, which only Layouts::ApplicationLayout renders.
    assert_select "body nav.navbar a.navbar-brand", text: "Cartodex"
  end

  # Both consent forms answer with a 302 to the *client's* origin
  # (https://claude.ai/…), and that is the whole point of the endpoint. Turbo
  # submits a form with fetch(), and fetch follows a cross-origin redirect only
  # if the final response carries Access-Control-Allow-Origin — an OAuth
  # callback never does. Left Turbo-driven, both buttons die in the browser with
  # "blocked by CORS policy" and the authorization code (or the deny) never
  # reaches the client, while the server-side tests above all pass.
  #
  # Only a native browser submit can follow that redirect as a top-level
  # navigation, so the opt-out has to be on the form itself.
  test "opts both consent forms out of Turbo so the browser can follow the cross-origin redirect" do
    sign_in @user

    get "/oauth/authorize", params: authorize_params

    assert_response :success
    assert_select "#consent-authorize-form[data-turbo='false']", count: 1
    assert_select "#consent-deny-form[data-turbo='false']", count: 1
  end

  test "escapes a client name that tries to inject markup" do
    @application.update!(name: "<script>alert(1)</script>")
    sign_in @user

    get "/oauth/authorize", params: authorize_params

    assert_response :success
    assert_not_includes response.body, "<script>alert(1)</script>"
  end
end
