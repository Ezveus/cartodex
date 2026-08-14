# The user-facing half of Doorkeeper's :authorized_applications controller,
# which routes.rb skips. Revocation is scoped to the current user's own tokens:
# an application is shared between users, so revoking it must never reach past
# the person clicking the button.
class ConnectedAppsController < ApplicationController
  def destroy
    current_user_tokens.find_each(&:revoke)
    # An authorization code not yet exchanged is a credential too: it survives
    # for ten minutes and redeems into a fresh access + refresh token pair.
    # Revoking only the tokens would let a connection the user just cut come
    # straight back, so the grants go with them.
    current_user_grants.find_each(&:revoke)

    redirect_to settings_path, notice: "Connection revoked."
  end

  private

  # The same set Settings::ConnectedAppsSection lists — unrevoked, regardless of
  # expiry. An expired access token still carries a working refresh token, so
  # "not revoked" is what "connected" means on both sides.
  def current_user_tokens
    Doorkeeper::AccessToken
      .where(resource_owner_id: current_user.id, revoked_at: nil, application_id: params[:id])
  end

  def current_user_grants
    Doorkeeper::AccessGrant
      .where(resource_owner_id: current_user.id, revoked_at: nil, application_id: params[:id])
  end
end
