class McpTokensController < ApplicationController
  def create
    raw = current_user.regenerate_api_token(expires_in: User.lifetime_for(params[:lifetime]))

    # Never cache the one response that carries the raw token in its body.
    response.cache_control[:no_store] = true

    respond_to do |format|
      # Rendered into the response body and nowhere else. flash would serialise
      # the raw token into the session cookie; Turbo Drive, meanwhile, ignores a
      # plain 200 HTML response to a form POST, so a Turbo Stream it is.
      # Phlex components respond to render_in, which TagBuilder#render_template
      # takes directly — no render_to_string indirection needed.
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "mcp-token",
          Settings::McpTokenSection.new(user: current_user, raw_token: raw)
        )
      end

      # Turbo is not guaranteed to be there: with JS blocked, or the importmap
      # asset failing to load, the browser submits the form natively and asks for
      # text/html. Answering that with a turbo-stream body makes the browser
      # download the response — writing the raw token, in cleartext, to the
      # user's disk, which is precisely what rendering it and nothing else is
      # meant to avoid. So render the settings page, reveal included: the same
      # one-shot disclosure, on screen only. Redirecting would be tidier but
      # would throw away the only copy of a token that is already live.
      format.html do
        @user = current_user
        @raw_token = raw
        render template: "settings/show"
      end
    end
  end

  # Idempotent: revoking with no token in place is not an error.
  def destroy
    current_user.revoke_api_token!
    redirect_to settings_path, notice: "MCP token revoked."
  end
end
