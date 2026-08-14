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

    # One token per application: the earliest still-active one, so the
    # displayed "connected since" date reflects the original authorization
    # rather than a later token refresh.
    def connections
      @connections ||= Doorkeeper::AccessToken
        .where(resource_owner_id: @user.id, revoked_at: nil)
        .includes(:application)
        .group_by(&:application)
        .filter_map { |application, tokens| [ application, tokens.min_by(&:created_at) ] if application }
    end

    def empty_state
      p(class: "settings-empty") { "No connected applications yet." }
    end

    def list
      ul(class: "settings-list") do
        connections.each { |application, first_token| row(application, first_token) }
      end
    end

    def row(application, first_token)
      li(class: "settings-list-item", data: { testid: "connected-app" }) do
        strong { application.name }
        span(class: "settings-list-meta") do
          plain "#{scope_summary(first_token)} — connected #{first_token.created_at.to_date.to_fs(:long)}"
        end
        revoke_button(application)
      end
    end

    def scope_summary(token)
      token.scopes.include?("mcp:write") ? "Read and write" : "Read only"
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
