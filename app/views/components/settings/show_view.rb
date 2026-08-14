module Settings
  class ShowView < ApplicationComponent
    # raw_token is set only by the non-Turbo fallback of
    # McpTokensController#create, which re-renders this whole page rather than a
    # Turbo Stream fragment; on a plain GET it is nil and no token is revealed.
    def initialize(user:, raw_token: nil)
      @user = user
      @raw_token = raw_token
    end

    def view_template
      div(class: "admin-container") do
        render Ui::PageHeader.new(title: "Settings")
        render Settings::McpTokenSection.new(user: @user, raw_token: @raw_token)
        render Settings::ConnectedAppsSection.new(user: @user)
      end
    end
  end
end
