class McpTokensController < ApplicationController
  def create
    raw = current_user.regenerate_api_token(expires_in: requested_lifetime)

    # Never cache the one response that carries the raw token in its body.
    response.cache_control[:no_store] = true

    # Rendered into the response body and nowhere else. flash would serialise
    # the raw token into the session cookie; Turbo Drive, meanwhile, ignores a
    # plain 200 HTML response to a form POST, so a Turbo Stream it is.
    # Phlex components respond to render_in, which TagBuilder#render_template
    # takes directly — no render_to_string indirection needed.
    render turbo_stream: turbo_stream.replace(
      "mcp-token",
      Settings::McpTokenSection.new(user: current_user, raw_token: raw)
    )
  end

  # Idempotent: revoking with no token in place is not an error.
  def destroy
    current_user.revoke_api_token!
    redirect_to settings_path, notice: "MCP token revoked."
  end

  private

  # The lifetime arrives from a form, so it is untrusted: resolve it through
  # User::TOKEN_LIFETIMES and fall back to the default rather than honouring an
  # arbitrary value or raising.
  def requested_lifetime
    key = params[:lifetime].presence
    key = User::DEFAULT_LIFETIME_KEY unless User::TOKEN_LIFETIMES.key?(key)
    User::TOKEN_LIFETIMES.fetch(key)
  end
end
