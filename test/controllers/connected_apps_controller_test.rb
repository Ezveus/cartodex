require "test_helper"

class ConnectedAppsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @other = users(:two)
    @application = Doorkeeper::Application.create!(
      name: "Claude",
      redirect_uri: "https://claude.ai/api/mcp/auth_callback",
      scopes: "mcp:read mcp:write"
    )
    sign_in @user
  end

  def token_for(user, scopes: "mcp:read mcp:write")
    Doorkeeper::AccessToken.create!(
      application: @application, resource_owner_id: user.id, scopes: scopes
    )
  end

  test "settings lists the user's connected applications and their scopes" do
    token_for(@user)

    get settings_path

    assert_response :success
    assert_select "[data-testid='connected-app']", count: 1
    assert_select "[data-testid='connected-app']", text: /Claude/
  end

  test "settings does not list another user's connections" do
    token_for(@other)

    get settings_path

    assert_select "[data-testid='connected-app']", count: 0
  end

  test "revoking a connection kills its tokens" do
    token = token_for(@user)

    delete connected_app_path(@application)

    assert_redirected_to settings_path
    assert token.reload.revoked?
  end

  test "revoking cannot touch another user's tokens" do
    mine = token_for(@user)
    theirs = token_for(@other)

    delete connected_app_path(@application)

    assert mine.reload.revoked?
    assert_not theirs.reload.revoked?
  end
end
