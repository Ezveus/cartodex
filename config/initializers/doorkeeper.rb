# frozen_string_literal: true

Doorkeeper.configure do
  orm :active_record

  # Doorkeeper runs its authorization endpoint inside the app's session, so the
  # resource owner is simply the signed-in Devise user. store_location_for makes
  # Devise return here after sign-in, which matters because the authorization
  # URL carries the PKCE challenge and state — losing it would break the flow.
  resource_owner_authenticator do
    current_user || begin
      store_location_for(:user, request.fullpath)
      redirect_to(new_user_session_path)
    end
  end

  # OAuth 2.1: authorization code only, PKCE mandatory. No implicit, no
  # password, no client credentials — an MCP client always acts for a user.
  grant_flows %w[authorization_code]
  force_pkce
  # Doorkeeper defaults this to %w[plain S256]. The "plain" method sends the
  # PKCE challenge in the clear during /oauth/authorize, so it *is* the
  # verifier the token endpoint later checks — an interceptor who captured the
  # authorization request already holds everything needed to redeem the code,
  # defeating PKCE entirely. The metadata document (oauth/metadata_controller)
  # already advertises S256 only; this makes the server actually enforce that.
  pkce_code_challenge_methods %w[S256]
  use_refresh_token

  # Same reasoning as users.api_token_digest: a database read must never yield a
  # usable credential.
  hash_token_secrets
  hash_application_secrets

  # mcp:read is what a client gets if it asks for nothing. mcp:write is optional
  # so the consent screen can withhold it and still produce a working connector.
  default_scopes  :"mcp:read"
  optional_scopes :"mcp:write"

  # Model-layer backstop to Oauth::ClientRegistrar's own scope check, the same
  # role RedirectUriValidator already plays for redirect_uri: without this,
  # ClientRegistrar::SERVER_SCOPES is the *only* thing standing between a
  # registration request and an application holding a scope this server never
  # configured. Doorkeeper leaves this disabled by default.
  enforce_configured_scopes

  access_token_expires_in 2.hours

  # Every client must be consented to explicitly. Dynamic registration means any
  # party can create a client, so silent authorization would be a hole.
  skip_authorization { false }

  # Doorkeeper's own RedirectUriValidator forces HTTPS on every redirect_uri in
  # every non-development environment by default, with no loopback exception.
  # Oauth::ClientRegistrar deliberately allows plain HTTP for CLI clients
  # binding an ephemeral local port (Oauth::ClientRegistrar::PLAIN_HTTP_HOSTS);
  # without this override, Doorkeeper's model-level validation would reject
  # those applications before ClientRegistrar's own checks ever ran, in test
  # and production alike.
  force_ssl_in_redirect_uri ->(uri) { !Oauth::ClientRegistrar::PLAIN_HTTP_HOSTS.include?(uri.host) }
end

# Doorkeeper 5.9's `force_pkce` only requires PKCE from non-confidential
# clients (see doorkeeper-gem/doorkeeper#1705 and the
# `Doorkeeper::OAuth::PreAuthorization#validate_code_challenge` hard-coded
# `return true if client.confidential`) — confidential clients are exempt.
# OAuth 2.1 has no such exemption: every authorization code exchange must
# carry a PKCE challenge, confidential client or not. There is no config flag
# for this in 5.9.6, so the check is patched to drop the exemption, while
# still honoring `force_pkce?` as the on/off switch.
Doorkeeper::OAuth::PreAuthorization.prepend(Module.new do
  def validate_code_challenge
    return true unless Doorkeeper.config.force_pkce?
    return true if code_challenge.present?

    @invalid_request_reason = :invalid_code_challenge
    false
  end
end)
