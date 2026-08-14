module Oauth
  # Registration is open to anyone, so scanners and abandoned setup attempts
  # would grow oauth_applications without bound. An application that has neither
  # an access grant nor an access token was never authorized by anyone: deleting
  # it can cost nobody a working connector.
  #
  # The grace period is generous on purpose. Registration and authorization are
  # separate round-trips, and a user who registers then goes to find their
  # password must still be able to finish.
  class PurgeStaleApplicationsJob < ApplicationJob
    queue_as :default

    GRACE_PERIOD = 7.days

    def perform
      Doorkeeper::Application
        .where(created_at: ..GRACE_PERIOD.ago)
        .where.missing(:access_tokens)
        .where.missing(:access_grants)
        .delete_all
    end
  end
end
