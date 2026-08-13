require "test_helper"

class McpTokensControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    sign_in @user
  end

  # Only the digest is stored, so the test cannot know the token in advance:
  # it reads the revealed value back out of the response.
  def revealed_token
    css_select("#mcp-token-value").first.text.strip
  end

  test "create reveals a token that actually authenticates" do
    post mcp_token_path, params: { lifetime: "30d" }, as: :turbo_stream

    assert_response :success
    token = revealed_token
    assert token.present?
    assert_equal @user, User.authenticate_api_token(token)
  end

  test "create honours the requested lifetime" do
    post mcp_token_path, params: { lifetime: "30d" }, as: :turbo_stream

    assert_in_delta 30.days.from_now.to_i, @user.reload.api_token_expires_at.to_i, 60
  end

  test "create falls back to the default lifetime when the value is unknown" do
    post mcp_token_path, params: { lifetime: "bogus" }, as: :turbo_stream

    assert_in_delta 90.days.from_now.to_i, @user.reload.api_token_expires_at.to_i, 60
  end

  test "create falls back to the default lifetime when the value is missing" do
    post mcp_token_path, as: :turbo_stream

    assert_in_delta 90.days.from_now.to_i, @user.reload.api_token_expires_at.to_i, 60
  end

  test "create with the never lifetime stores no expiry" do
    post mcp_token_path, params: { lifetime: "never" }, as: :turbo_stream

    assert_nil @user.reload.api_token_expires_at
  end

  test "create replaces the token section by id" do
    post mcp_token_path, as: :turbo_stream

    assert_match %r{<turbo-stream action="replace" target="mcp-token">}, response.body
  end

  # The design decision this locks in: the raw token is rendered into the
  # response body and nowhere else.
  #
  # Assert on flash and session, not only on Set-Cookie. Rails encrypts the
  # session cookie, so a token stashed in flash never appears as plaintext in a
  # header — a header-only assertion would pass against the very regression it
  # claims to prevent. The Set-Cookie assertion stays because it catches a
  # different mistake: writing the token to an unencrypted cookie directly.
  test "the raw token never reaches flash, session or a cookie, and never survives a reload" do
    post mcp_token_path, as: :turbo_stream
    token = revealed_token

    assert_not_includes flash.to_hash.values.join(" "), token
    assert_not_includes session.to_hash.values.map(&:to_s).join(" "), token
    assert_no_match(/#{Regexp.escape(token)}/, response.headers.to_h.to_s)

    get settings_path

    assert_response :success
    assert_no_match(/#{Regexp.escape(token)}/, response.body)
    assert_not_includes flash.to_hash.values.join(" "), token
  end

  # Turbo can be absent — JS blocked, or the importmap asset failing to load —
  # and the browser then submits the form natively. Answering that with a
  # turbo-stream body made the browser download the response, writing the raw
  # token to the user's disk in cleartext.
  test "create answers a non-Turbo submission with a renderable HTML page" do
    post mcp_token_path, params: { lifetime: "30d" }

    assert_response :success
    assert_equal "text/html", response.media_type
    assert_includes response.headers["Cache-Control"].to_s, "no-store"
    assert_equal @user, User.authenticate_api_token(revealed_token), "the token must still be revealed once"
  end

  test "create keeps the requested lifetime selected in the re-rendered form" do
    post mcp_token_path, params: { lifetime: "1y" }, as: :turbo_stream

    assert_response :success
    assert_select "option[value=?][selected]", "1y"
    assert_select "option[value=?][selected]", "90d", count: 0
  end

  test "create with the never lifetime keeps Never selected" do
    post mcp_token_path, params: { lifetime: "never" }, as: :turbo_stream

    assert_response :success
    assert_select "option[value=?][selected]", "never"
  end

  test "the reveal opts out of both the Turbo snapshot and the browser bfcache" do
    post mcp_token_path, as: :turbo_stream

    assert_response :success
    assert_select ".settings-reveal[data-turbo-temporary][data-controller=?]", "ephemeral-secret"
  end

  test "create requires authentication" do
    sign_out @user

    post mcp_token_path, as: :turbo_stream

    assert_redirected_to new_user_session_path
  end

  test "destroy revokes the token" do
    raw = @user.regenerate_api_token

    delete mcp_token_path

    assert_redirected_to settings_path
    assert_nil User.authenticate_api_token(raw)
    assert_not @user.reload.api_token?
  end

  test "destroy is idempotent when there is no token" do
    @user.revoke_api_token!

    delete mcp_token_path

    assert_redirected_to settings_path
    assert_not @user.reload.api_token?
  end
end
