module Oauth
  # Shared by the authorization and token endpoints so a client cannot pass the
  # check at one and slip a different resource past the other.
  module ResourceIndicatorEnforcement
    extend ActiveSupport::Concern

    included do
      before_action :validate_resource_indicator!
    end

    private

    def validate_resource_indicator!
      return if ResourceIndicator.valid?(params[:resource], canonical_resource_uri)

      render json: {
        error: "invalid_target",
        error_description: "resource must be #{canonical_resource_uri}"
      }, status: :bad_request
    end

    # Delegates so the canonical URI has exactly one definition. Task 2 built the
    # same expression privately in Oauth::MetadataController; this task moves the
    # single copy into ResourceIndicator and points both callers at it. Two
    # independent definitions of this value would be a real hazard, not a style
    # nit: if they ever diverged, the metadata document would advertise one
    # resource while the token endpoint accepted another.
    def canonical_resource_uri
      ResourceIndicator.canonical_uri(root_url)
    end
  end
end
