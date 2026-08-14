require "test_helper"

class OauthResourceIndicatorTest < ActionDispatch::IntegrationTest
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
    sign_in @user

    # Warm the integration session with a real request before any test builds a
    # `resource` param off `root_url`. Called cold, `root_url` falls back to
    # config/application.rb's ENV-derived default_url_options ("localhost:3000")
    # instead of the request host ("www.example.com") the controller actually
    # sees, which would make the "accepts" tests send a resource that does not
    # match what the controller computes as canonical — a self-inflicted
    # mismatch, not a bug in the validator.
    get "/up"
  end

  def authorize_params(overrides = {})
    {
      client_id: @application.uid,
      redirect_uri: @application.redirect_uri,
      response_type: "code",
      scope: "mcp:read",
      code_challenge: @challenge,
      code_challenge_method: "S256"
    }.merge(overrides)
  end

  test "accepts an authorization carrying the canonical resource URI" do
    post "/oauth/authorize", params: authorize_params(resource: "#{root_url.chomp('/')}/mcp")

    assert_response :redirect
  end

  test "accepts an authorization with no resource parameter at all" do
    # The specification obliges clients to send it; refusing those that do not
    # would cost interoperability and buy nothing while we host one resource.
    post "/oauth/authorize", params: authorize_params

    assert_response :redirect
  end

  test "accepts an uppercase scheme and host" do
    # Built from root_url's own scheme (test env serves http, not https) rather
    # than a hardcoded "HTTPS://" — this exercises case-insensitivity, not a
    # scheme mismatch.
    uri = URI.parse(root_url)
    post "/oauth/authorize", params: authorize_params(
      resource: "#{uri.scheme.upcase}://#{uri.host.upcase}/mcp"
    )

    assert_response :redirect
  end

  test "rejects an authorization aimed at another resource" do
    post "/oauth/authorize", params: authorize_params(resource: "https://evil.example.com/mcp")

    assert_response :bad_request
    assert_equal "invalid_target", JSON.parse(response.body)["error"]
  end

  test "rejects a resource carrying a fragment" do
    post "/oauth/authorize", params: authorize_params(resource: "#{root_url.chomp('/')}/mcp#x")

    assert_response :bad_request
    assert_equal "invalid_target", JSON.parse(response.body)["error"]
  end

  test "rejects a resource carrying userinfo" do
    # user@ resolves to the same host and would silently normalise to the
    # canonical string if userinfo were not checked — it does not point
    # anywhere else, but RFC 8707 canonical resource identifiers carry no
    # userinfo, so this must be rejected the same way a fragment is.
    uri = URI.parse(root_url)
    post "/oauth/authorize", params: authorize_params(resource: "#{uri.scheme}://user@#{uri.host}/mcp")

    assert_response :bad_request
    assert_equal "invalid_target", JSON.parse(response.body)["error"]
  end

  test "accepts a resource with a trailing slash on the path" do
    # Pinned tolerance, not an accident: the MCP specification notes both
    # trailing-slash forms are valid URIs and recommends the bare one, so a
    # client sending the other form should not be rejected over it.
    post "/oauth/authorize", params: authorize_params(resource: "#{root_url.chomp('/')}/mcp/")

    assert_response :redirect
  end

  test "rejects a token request aimed at another resource" do
    post "/oauth/authorize", params: authorize_params
    code = Rack::Utils.parse_query(URI.parse(response.location).query)["code"]

    post "/oauth/token", params: {
      grant_type: "authorization_code", code: code,
      redirect_uri: @application.redirect_uri,
      client_id: @application.uid, client_secret: @application.plaintext_secret,
      code_verifier: @verifier, resource: "https://evil.example.com/mcp"
    }

    assert_response :bad_request
    assert_equal "invalid_target", JSON.parse(response.body)["error"]
  end
end
