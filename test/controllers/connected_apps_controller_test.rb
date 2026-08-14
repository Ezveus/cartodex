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

  def token_for(user, scopes: "mcp:read mcp:write", created_at: Time.current, expires_in: nil)
    Doorkeeper::AccessToken.create!(
      application: @application, resource_owner_id: user.id, scopes: scopes,
      created_at: created_at, expires_in: expires_in, use_refresh_token: true
    )
  end

  def grant_for(user)
    Doorkeeper::AccessGrant.create!(
      application: @application, resource_owner_id: user.id, scopes: "mcp:read",
      redirect_uri: @application.redirect_uri, expires_in: 10.minutes.to_i
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

  test "two tokens for the same application render a single row" do
    token_for(@user, created_at: 2.days.ago)
    token_for(@user, created_at: 1.day.ago)

    get settings_path

    assert_select "[data-testid='connected-app']", count: 1
  end

  test "the row shows the union of scopes across the application's live tokens" do
    # Older token is read-only; a later re-authorization added write. If the
    # row only looked at one token (say, the earliest), this would read
    # "Read only" instead of the union.
    token_for(@user, scopes: "mcp:read", created_at: 2.days.ago)
    token_for(@user, scopes: "mcp:read mcp:write", created_at: 1.day.ago)

    get settings_path

    assert_select "[data-testid='connected-app']", count: 1
    assert_select "[data-testid='connected-app']", text: /Read and write/
  end

  test "an application whose access token has expired is still listed" do
    # The connection is alive: the access token lapsed after two hours but its
    # refresh token did not, so the client can mint a new one whenever it likes.
    # The page previously filtered on Doorkeeper's #accessible? and hid exactly
    # this row, while #destroy scoped on revoked_at — which made the revoke
    # button, the only such control in the product, unreachable for every
    # connection not being used at that very second.
    token = token_for(@user, expires_in: 10, created_at: 1.hour.ago)
    assert_not token.accessible?, "fixture must be an expired-but-unrevoked token"
    assert token.refresh_token.present?, "fixture must still carry a refresh token"

    get settings_path

    assert_select "[data-testid='connected-app']", count: 1
    assert_select "[data-testid='connected-app']", text: /Claude/
  end

  test "a revoked connection stops being listed" do
    token_for(@user)

    delete connected_app_path(@application)
    get settings_path

    assert_select "[data-testid='connected-app']", count: 0
  end

  test "revoking a connection also kills its unredeemed authorization codes" do
    # An authorization code is a credential with a ten-minute life that redeems
    # into a fresh access + refresh token pair. Leaving it alive would let the
    # connection the user just cut walk straight back in.
    token_for(@user)
    grant = grant_for(@user)

    delete connected_app_path(@application)

    assert grant.reload.revoked?
  end

  test "revoking cannot touch another user's authorization codes" do
    theirs = grant_for(@other)

    delete connected_app_path(@application)

    assert_not theirs.reload.revoked?
  end
end
