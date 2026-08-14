# The user-facing half of Doorkeeper's :authorized_applications controller,
# which routes.rb skips. Revocation is scoped to the current user's own tokens:
# an application is shared between users, so revoking it must never reach past
# the person clicking the button.
class ConnectedAppsController < ApplicationController
  def destroy
    current_user_tokens.where(application_id: params[:id]).find_each(&:revoke)

    redirect_to settings_path, notice: "Connection revoked."
  end

  private

  def current_user_tokens
    Doorkeeper::AccessToken.where(resource_owner_id: current_user.id, revoked_at: nil)
  end
end
