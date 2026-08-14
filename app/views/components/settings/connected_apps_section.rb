module Settings
  # OAuth clients the user has authorized. One row per application, not per
  # token: a client refreshing its access token would otherwise pile up rows for
  # what the user experiences as a single connection.
  class ConnectedAppsSection < ApplicationComponent
    def initialize(user:)
      @user = user
    end

    def view_template
      section(id: "connected-apps", class: "settings-section") do
        h2 { "Connected applications" }
        p(class: "settings-section-lead") do
          plain "MCP clients you have authorized to reach your collection and decks."
        end
        connections.any? ? list : empty_state
      end
    end

    private

    # Grouped by application, keeping every live token (not just the earliest):
    # re-authorizing the same client without reuse_access_token or revoke_previous_client_credentials_authorizations
    # leaves the old token in place alongside the new one, so a single token
    # would silently under-report what the client currently holds. "Live" means
    # Doorkeeper's own #accessible? (not expired, not revoked) — the same test
    # the MCP endpoint itself gates on — so an application whose tokens have all
    # expired drops off the list entirely instead of lingering as "connected"
    # forever. Filtering in Ruby after the DB query is fine at this scale: a
    # user has a handful of connections, not thousands.
    def connections
      @connections ||= Doorkeeper::AccessToken
        .where(resource_owner_id: @user.id, revoked_at: nil)
        .includes(:application)
        .select(&:accessible?)
        .group_by(&:application)
        .filter_map { |application, tokens| [ application, tokens ] if application }
    end

    def empty_state
      p(class: "settings-empty") { "No connected applications yet." }
    end

    def list
      ul(class: "settings-list") do
        connections.each { |application, tokens| row(application, tokens) }
      end
    end

    def row(application, tokens)
      li(class: "settings-list-item", data: { testid: "connected-app" }) do
        strong { application.name }
        span(class: "settings-list-meta") do
          plain "#{scope_summary(tokens)} — connected #{connected_since(tokens)}"
        end
        revoke_button(application)
      end
    end

    # Union of scopes across every live token for the application: answers
    # "what can this client do right now", not "what did its oldest token get".
    def scope_summary(tokens)
      tokens.any? { |token| token.scopes.include?("mcp:write") } ? "Read and write" : "Read only"
    end

    # The earliest *live* token's date — a token that has since expired or been
    # revoked no longer counts as part of this connection's history.
    def connected_since(tokens)
      tokens.min_by(&:created_at).created_at.to_date.to_fs(:long)
    end

    def revoke_button(application)
      form_with url: connected_app_path(application), method: :delete, class: "settings-list-revoke" do
        render Ui::Button.new(
          label: "Revoke",
          variant: :danger,
          data: { turbo_confirm: "Revoke this connection? #{application.name} will stop working." }
        )
      end
    end
  end
end
