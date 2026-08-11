require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    sign_in @user
  end

  test "requires authentication" do
    sign_out @user

    get settings_path

    assert_redirected_to new_user_session_path
  end

  test "shows the generate prompt when the user has no token" do
    @user.revoke_api_token!

    get settings_path

    assert_response :success
    assert_select "#mcp-token"
    assert_select "#mcp-token", text: /No token/
    assert_select "#mcp-token button", text: "Generate token"
    assert_select "#mcp-token-revoke", count: 0
  end

  test "shows the metadata and a rotate action when the user has a token" do
    @user.regenerate_api_token(expires_in: 30.days)

    get settings_path

    assert_response :success
    assert_select "#mcp-token button", text: "Rotate token"
    assert_select "#mcp-token-revoke"
    assert_select "#mcp-token", text: /Created/
    assert_select "#mcp-token", text: /Expires/
  end

  test "flags an expired token" do
    @user.regenerate_api_token
    @user.update_column(:api_token_expires_at, 1.day.ago)

    get settings_path

    assert_response :success
    assert_select "#mcp-token .badge", text: "Expired"
  end

  test "never renders a raw token on a plain page load" do
    @user.regenerate_api_token

    get settings_path

    assert_response :success
    assert_select "#mcp-token-value", count: 0
  end
end
