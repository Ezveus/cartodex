module Oauth
  # Subclasses Doorkeeper's authorization endpoint. It exists so the consent
  # screen and the RFC 8707 resource check have a home; the authorization logic
  # itself stays Doorkeeper's.
  class AuthorizationsController < Doorkeeper::AuthorizationsController
    include ResourceIndicatorEnforcement

    # The consent form never posts a `scope` field — Doorkeeper::PreAuthorization
    # reads only `params[:scope]` on POST and, finding it blank, falls back to
    # `default_scopes` ("mcp:read"), silently discarding a checked mcp:write box.
    # A round-trip test that actually posts the rendered form's own params (not
    # a hand-built `scope` string) is what caught this: translate the consent
    # form's checkbox choice into the field Doorkeeper actually looks at, before
    # it rebuilds pre_auth from params.
    before_action :narrow_scopes_to_consent, only: :create

    def narrow_scopes_to_consent
      # This only intersects against the server's whole scope vocabulary, not
      # against what the request originally asked for or what the client is
      # entitled to — and that is fine, not a security boundary to shore up.
      # Doorkeeper's own PreAuthorization#validate_scopes independently bounds
      # the eventual grant to client.scopes, and CSRF protection covers a
      # forged POST to this action. This line only decides which checked boxes
      # survive into params[:scope] before Doorkeeper looks at it.
      granted = Array(params[:granted_scopes]).reject(&:blank?)
      params[:scope] = (granted & Oauth::MetadataController::SCOPES).join(" ") if granted.any?
    end
  end
end
