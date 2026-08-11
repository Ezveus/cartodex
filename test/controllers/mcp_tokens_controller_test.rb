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
  # response body and nowhere else. Routing it through flash would serialise it
  # into the session cookie, i.e. onto the browser's disk in clear text.
  test "the raw token never reaches a cookie and never survives a reload" do
    post mcp_token_path, as: :turbo_stream
    token = revealed_token

    assert_no_match(/#{Regexp.escape(token)}/, response.headers.to_h.to_s)

    get settings_path

    assert_response :success
    assert_no_match(/#{Regexp.escape(token)}/, response.body)
    assert_no_match(/#{Regexp.escape(token)}/, response.headers.to_h.to_s)
  end

  test "create requires authentication" do
    sign_out @user

    post mcp_token_path, as: :turbo_stream

    assert_redirected_to new_user_session_path
  end
end
