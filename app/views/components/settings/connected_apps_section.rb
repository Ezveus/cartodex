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

    # Grouped by application, keeping every unrevoked token (not just the
    # earliest): re-authorizing the same client without reuse_access_token or
    # revoke_previous_client_credentials_authorizations leaves the old token in
    # place alongside the new one, so a single token would silently under-report
    # what the client currently holds.
    #
    # "Live" is `revoked_at: nil`, deliberately NOT Doorkeeper's #accessible?.
    # An access token expires after two hours but its refresh token does not, so
    # an unrevoked row is a fully working connection the client can resume at
    # any moment. Filtering on #accessible? here hid every connection that was
    # not being actively used at that second, while ConnectedAppsController
    # #destroy scoped on revoked_at — the page and the only revocation control
    # in the product disagreed, and in the steady state the control was simply
    # unreachable. This query and #destroy must stay the same set.
    def connections
      @connections ||= Doorkeeper::AccessToken
        .where(resource_owner_id: @user.id, revoked_at: nil)
        .includes(:application)
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

    # Union of scopes across every unrevoked token for the application: answers
    # "what can this client do right now", not "what did its oldest token get".
    # An expired access token still counts, because refreshing it yields a new
    # one with the same scopes — the client's reach is unchanged by the clock.
    def scope_summary(tokens)
      tokens.any? { |token| token.scopes.include?("mcp:write") } ? "Read and write" : "Read only"
    end

    # The earliest unrevoked token's date: when this still-standing connection
    # began. A revoked token is genuinely gone and drops out of the history;
    # a merely expired one does not, since the connection outlived it.
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
