module Oauth
  # RFC 7591 registration endpoint. ActionController::API rather than ::Base:
  # this is a machine endpoint with no session and no CSRF token to present.
  #
  # Unauthenticated by necessity, so it is throttled per IP — the one place in
  # this feature where an IP key is the right choice, because no user exists yet.
  class RegistrationsController < ActionController::API
    RATE_LIMIT_TO = 20
    RATE_LIMIT_WITHIN = 1.minute

    # Same call-time Rails.cache proxy as Mcp::ServerController, so tests can
    # swap in a real store where the test environment's :null_store would make
    # the limiter a no-op.
    RATE_LIMIT_STORE = Module.new do
      def self.increment(...)
        Rails.cache.increment(...)
      end
    end

    rate_limit to: RATE_LIMIT_TO, within: RATE_LIMIT_WITHIN,
      name: "oauth-register", store: RATE_LIMIT_STORE, only: :create

    def create
      application = ClientRegistrar.call(registration_metadata)

      render json: registration_response(application), status: :created
    rescue ClientRegistrar::InvalidMetadata => e
      render json: { error: e.code, error_description: e.message }, status: :bad_request
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
