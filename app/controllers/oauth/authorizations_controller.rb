module Oauth
  # Subclasses Doorkeeper's authorization endpoint. It exists so the consent
  # screen and the RFC 8707 resource check (added in the next task) have a home;
  # the authorization logic itself stays Doorkeeper's.
  class AuthorizationsController < Doorkeeper::AuthorizationsController
  end
end
