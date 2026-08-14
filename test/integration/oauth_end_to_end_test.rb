require "test_helper"
require_relative "../support/oauth_consent_form"

# The whole connector flow, discovered from nothing but the MCP URL, exactly as
# a Claude web connector walks it: 401 challenge → protected-resource metadata →
# authorization-server metadata → dynamic registration → consent screen → code
# exchange with PKCE → tools/list → a write call.
#
# Every other OAuth test on this branch covers one segment. The defects that
# shipped — a refresh token that was never rotated, a live connection invisible
# in /settings, a 500 from an opaque `resource` — all lived in the seams between
# segments, which is what this test exists to hold.
#
# Nothing here is hardcoded that a real client would discover: every URL comes
# out of the previous step's response body or header.
class OauthEndToEndTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include OauthConsentForm

  MCP_HEADERS = {
    "Content-Type" => "application/json",
    "Accept" => "application/json, text/event-stream"
  }.freeze

  setup do
    @user = users(:one)
    @card = cards(:trainer_card)
    @verifier = SecureRandom.urlsafe_base64(64)
    @challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(@verifier), padding: false)
    @state = SecureRandom.urlsafe_base64(16)
  end

  def mcp_call(body, token: nil)
    headers = MCP_HEADERS.dup
    headers["Authorization"] = "Bearer #{token}" if token
    post "/mcp", params: body.to_json, headers: headers
  end

  def json = JSON.parse(response.body)

  def path_of(url) = URI.parse(url).request_uri

  test "connects a client from the bare MCP URL through to a write call" do
    # 1. The client knows only the MCP URL. It calls it and is challenged.
    mcp_call({ jsonrpc: "2.0", id: 1, method: "tools/list", params: {} })
    assert_response :unauthorized
    challenge = response.headers["WWW-Authenticate"]
    assert_match(/\ABearer /, challenge)
    resource_metadata_url = challenge[/resource_metadata="([^"]+)"/, 1]
    assert resource_metadata_url.present?, "the 401 must point at the RFC 9728 document"

    # 2. RFC 9728: which authorization server guards this resource.
    get path_of(resource_metadata_url)
    assert_response :success
    protected_resource = json
    canonical_resource = protected_resource["resource"]
    assert_equal "http://www.example.com/mcp", canonical_resource
    assert_includes protected_resource["scopes_supported"], "mcp:write"
    authorization_server = protected_resource["authorization_servers"].first

    # 3. RFC 8414: where that server's endpoints are.
    get "#{path_of(authorization_server)}.well-known/oauth-authorization-server"
    assert_response :success
    metadata = json
    assert_equal [ "S256" ], metadata["code_challenge_methods_supported"]
    assert_includes metadata["grant_types_supported"], "refresh_token"

    # 4. RFC 7591: the client registers itself. No credential exists yet.
    post path_of(metadata["registration_endpoint"]),
      params: {
        client_name: "Claude",
        redirect_uris: [ "https://claude.ai/api/mcp/auth_callback" ],
        token_endpoint_auth_method: "client_secret_post"
      }.to_json,
      headers: { "Content-Type" => "application/json" }
    assert_response :created
    client = json
    assert client["client_id"].present?
    assert client["client_secret"].present?

    # 5. The user's browser lands on the consent screen. Anonymous first, to
    #    prove the sign-in detour keeps the authorization request intact.
    authorize_path = path_of(metadata["authorization_endpoint"])
    authorize_params = {
      client_id: client["client_id"],
      redirect_uri: client["redirect_uris"].first,
      response_type: "code",
      scope: "mcp:read mcp:write",
      state: @state,
      code_challenge: @challenge,
      code_challenge_method: "S256",
      resource: canonical_resource
    }

    get authorize_path, params: authorize_params
    assert_redirected_to new_user_session_path

    sign_in @user
    get authorize_path, params: authorize_params
    assert_response :success
    assert_select "[data-testid='consent-client-name']", text: /Claude/
    assert_select "[data-testid='consent-redirect-host']", text: /claude\.ai/

    # 6. The user approves. The POST is the rendered form's own fields, not a
    #    hand-built params hash — see OauthConsentForm.
    post authorize_path, params: harvest_form_params
    assert_response :redirect

    callback = URI.parse(response.location)
    assert_equal "claude.ai", callback.host
    query = Rack::Utils.parse_query(callback.query)
    code = query["code"]
    assert code.present?
    # CSRF protection for the client: a state that did not survive the round
    # trip means the client cannot tell its own request from an injected one.
    assert_equal @state, query["state"]

    # 7. Code exchange with the PKCE verifier and the resource indicator.
    post path_of(metadata["token_endpoint"]), params: {
      grant_type: "authorization_code",
      code: code,
      redirect_uri: client["redirect_uris"].first,
      client_id: client["client_id"],
      client_secret: client["client_secret"],
      code_verifier: @verifier,
      resource: canonical_resource
    }
    assert_response :success
    tokens = json
    assert tokens["access_token"].present?
    assert tokens["refresh_token"].present?
    assert_equal "mcp:read mcp:write", tokens["scope"]

    # 8. The call that was refused at step 1 now works, and consent granted
    #    mcp:write, so the write tools are advertised.
    mcp_call({ jsonrpc: "2.0", id: 2, method: "tools/list", params: {} }, token: tokens["access_token"])
    assert_response :success
    tool_names = json.dig("result", "tools").map { |tool| tool["name"] }
    assert_includes tool_names, "list_decks"
    assert_includes tool_names, "add_card_to_collection"

    # 9. And a write actually lands, under the right user.
    assert_nil @user.collections.find_by(card: @card)
    mcp_call({
      jsonrpc: "2.0", id: 3, method: "tools/call",
      params: { name: "add_card_to_collection", arguments: { card_id: @card.id, quantity: 3 } }
    }, token: tokens["access_token"])
    assert_response :success
    assert_equal 3, @user.collections.find_by(card: @card).quantity

    # 10. The connection the user just made is visible where they can revoke it.
    get settings_path
    assert_select "[data-testid='connected-app']", count: 1
    assert_select "[data-testid='connected-app']", text: /Claude/
  end

  test "a connector refused mcp:write at consent gets a read-only token" do
    # The same flow with the one box the user is allowed to uncheck, driven
    # through the rendered form rather than by narrowing the scope param.
    application = Doorkeeper::Application.create!(
      name: "Claude", redirect_uri: "https://claude.ai/api/mcp/auth_callback",
      scopes: "mcp:read mcp:write"
    )
    sign_in @user

    authorize_params = {
      client_id: application.uid, redirect_uri: application.redirect_uri,
      response_type: "code", scope: "mcp:read mcp:write", state: @state,
      code_challenge: @challenge, code_challenge_method: "S256"
    }
    get "/oauth/authorize", params: authorize_params
    assert_response :success

    post "/oauth/authorize", params: harvest_form_params(exclude_checkbox_values: [ "mcp:write" ])
    assert_response :redirect
    query = Rack::Utils.parse_query(URI.parse(response.location).query)
    assert_equal @state, query["state"]

    post "/oauth/token", params: {
      grant_type: "authorization_code", code: query["code"],
      redirect_uri: application.redirect_uri,
      client_id: application.uid, client_secret: application.plaintext_secret,
      code_verifier: @verifier
    }
    assert_response :success
    tokens = json
    assert_equal "mcp:read", tokens["scope"]

    mcp_call({ jsonrpc: "2.0", id: 1, method: "tools/list", params: {} }, token: tokens["access_token"])
    tool_names = json.dig("result", "tools").map { |tool| tool["name"] }
    assert_includes tool_names, "list_decks"
    assert_not_includes tool_names, "add_card_to_collection"
  end
end
