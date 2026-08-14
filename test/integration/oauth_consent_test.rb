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

  # Harvests the consent form actually rendered by the GET into the params a
  # browser would build from it: every hidden field, plus one value per
  # non-disabled checked checkbox. This is what stands between the two most
  # dangerous silent failures in this screen — a dropped code_challenge hidden
  # field, or a dropped hidden mirror of the disabled mcp:read checkbox — and a
  # test that would actually notice: hand-building the POST params, as
  # authorize_params does, can't see either regression because it never reads
  # the form at all.
  #
  # exclude_checkbox_values simulates the user unchecking a box: a disabled
  # checkbox is never in this set to begin with (real browsers don't submit
  # disabled inputs either), so excluding mcp:read here would prove nothing —
  # only a genuinely optional, checked box belongs in the argument.
  #
  # Scoped to #consent-authorize-form: the screen renders a second form (Deny,
  # DELETE) with its own hidden-field mirror right below it, method-override
  # field included — an unscoped query would harvest both indiscriminately and
  # hand the POST a stray _method=delete along with duplicate fields.
  def harvest_form_params(exclude_checkbox_values: [])
    params = Hash.new { |hash, key| hash[key] = [] }

    css_select("#consent-authorize-form input[type=hidden]").each { |field| collect_field(params, field) }
    css_select("#consent-authorize-form input[type=checkbox]:not([disabled])").each do |checkbox|
      next if exclude_checkbox_values.include?(checkbox["value"])

      collect_field(params, checkbox)
    end

    params
  end

  def collect_field(params, field)
    name = field["name"]
    if name.end_with?("[]")
      params[name.delete_suffix("[]")] << field["value"]
    else
      params[name] = field["value"]
    end
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

  test "escapes a client name that tries to inject markup" do
    @application.update!(name: "<script>alert(1)</script>")
    sign_in @user

    get "/oauth/authorize", params: authorize_params

    assert_response :success
    assert_not_includes response.body, "<script>alert(1)</script>"
  end
end
