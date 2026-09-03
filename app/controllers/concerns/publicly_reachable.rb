# A controller reachable without a session. The three things it does must never be separated:
# it drops the app-wide Devise gate for the actions it names, it makes Pundit's
# verify_authorized mandatory on *every* action of the controller, and it routes both
# "not for you" exceptions onto one renderer so that an unknown key and a private record are
# indistinguishable.
#
# Note what verify_authorized cannot do: a before_action that halts the chain skips the
# after_action too, so on a signed-out request to an owner-only action authenticate_user!
# redirects and this check never runs. It catches a missing `authorize` only on requests that
# reach the action. test/controllers/public_access_test.rb covers the other half by making the
# same requests signed in.
module PubliclyReachable
  extend ActiveSupport::Concern

  included do
    after_action :verify_authorized
    rescue_from ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError, with: :not_found
  end

  class_methods do
    def publicly_reachable(*actions)
      skip_before_action :authenticate_user!, only: actions
    end
  end

  private

  # The same static page the rest of the app serves. Not an in-app 404 with a navbar:
  # /tournaments/999 would keep serving this file, and a deck answering differently from
  # everything else is a difference nobody asked for.
  def not_found
    render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
  end
end
