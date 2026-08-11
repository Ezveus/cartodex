module Settings
  class ShowView < ApplicationComponent
    def initialize(user:)
      @user = user
    end

    def view_template
      div(class: "admin-container") do
        render Ui::PageHeader.new(title: "Settings")
        render Settings::McpTokenSection.new(user: @user)
      end
    end
  end
end
