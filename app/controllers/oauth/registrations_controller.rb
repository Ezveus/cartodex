module Oauth
  # RFC 7591 registration endpoint. ActionController::API rather than ::Base:
  # this is a machine endpoint with no session and no CSRF token to present.
  #
  # Unauthenticated by necessity, so it is throttled per IP — the one place in
  # this feature where an IP key is the right choice, because no user exists yet.
  class RegistrationsController < ActionController::API
    RATE_LIMIT_TO = 20
    RATE_LIMIT_WITHIN = 1.minute

    rate_limit to: RATE_LIMIT_TO, within: RATE_LIMIT_WITHIN,
      name: "oauth-register", store: RateLimitStore, only: :create

    def create
      application = ClientRegistrar.call(registration_metadata)

      render json: registration_response(application), status: :created
    rescue ClientRegistrar::InvalidMetadata => e
      render json: { error: e.code, error_description: e.message }, status: :bad_request
    rescue ActiveRecord::RecordInvalid => e
      # Two independent model-level validations can raise this once
      # ClientRegistrar's own checks have already run once: RedirectUriValidator
      # (a backstop for the fragment/http-scheme cases it also validates, see
      # config/initializers/doorkeeper.rb) and scopes_match_configured (a
      # backstop for its own scope allowlist, enabled by the same
      # enforce_configured_scopes). No application is created either way, but
      # which RFC 7591 error code is honest depends on which one fired — a
      # regression in the scope check is not a malformed redirect_uri, and
      # reporting it as one points a client at the wrong problem. uid
      # uniqueness (also validated at this layer) falls into the
      # invalid_client_metadata bucket too: a collision in a 256-bit
      # SecureRandom token is not a real-world event, and RFC 7591 gives this
      # endpoint no third code to spend on it.
      code = e.record.errors.attribute_names.include?(:redirect_uri) ? "invalid_redirect_uri" : "invalid_client_metadata"
      render json: { error: code, error_description: e.message }, status: :bad_request
    end

    private

    # params.to_unsafe_h is deliberate: RFC 7591 metadata is an open map whose
    # keys are defined by the RFC and its extensions, not by us. The service
    # reads only the keys it knows and validates each one, so permitting a fixed
    # list here would add no safety and would silently drop future metadata.
    def registration_metadata
      params.to_unsafe_h.except("controller", "action", "registration").stringify_keys
    end

    def registration_response(application)
      {
        client_id: application.uid,
        client_secret: application.confidential? ? application.plaintext_secret : nil,
        client_id_issued_at: application.created_at.to_i,
        client_secret_expires_at: 0,
        client_name: application.name,
        redirect_uris: application.redirect_uri.split("\n"),
        grant_types: %w[authorization_code refresh_token],
        response_types: [ "code" ],
        token_endpoint_auth_method: application.confidential? ? "client_secret_post" : "none",
        scope: application.scopes.to_s
      }.compact
    end
  end
end
